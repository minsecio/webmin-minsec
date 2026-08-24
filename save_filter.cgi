#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in);
ReadParse();
minsec::require_post();
minsec::require_acl('filters');
my $name = $in{'name'} || '';
error('Invalid filter name') if ($name !~ /\A[A-Za-z0-9_.-]+\z/);
my %policy = ('enabled' => $in{'enabled'} ? 'true' : 'false');
if (defined($in{'max_retries'}) && $in{'max_retries'} ne '') {
	error('Maximum retries must be a positive integer') if ($in{'max_retries'} !~ /^\d+$/ || !$in{'max_retries'});
	$policy{'maxretry'} = int($in{'max_retries'});
}
foreach my $field (qw(find_time ban_duration)) {
	my ($seconds, $duration_error) = minsec::validate_duration($in{$field}, 1);
	error(minsec::html_escape($duration_error)) if ($duration_error);
	my $key = $field eq 'find_time' ? 'findtime' : 'bantime';
	$policy{$key} = $seconds.'s' if (defined($seconds));
}
my $content = minsec::render_webmin_toml({'filters' => {$name => \%policy}});
my ($inspection, $inspect_error) = minsec::inspect();
error(minsec::html_escape($inspect_error)) if ($inspect_error);
my $config_dir = minsec::inspection_path($inspection, 'config_dir') || minsec::settings()->{'config_dir'};
my $filename = 'webmin-filter-'.$name.'.toml';
my $path = "$config_dir/conf.d/$filename";
my ($safe_path, $path_error) = minsec::allowed_file_path($path, $inspection, 1, 'dropin');
error(minsec::html_escape($path_error)) if ($path_error);
my (undef, $save_error) = minsec::staged_change('config_dir' => $config_dir, 'path' => $safe_path, 'content' => $content);
error(minsec::html_escape($save_error)) if ($save_error);
webmin_log('save', 'filter', $name, \%policy);
if (($in{'operation'} || '') eq 'restart') {
	minsec::require_acl('service');
	my ($ok, $restart_error) = minsec::service_action('restart');
	error(minsec::html_escape($restart_error)) if (!$ok);
}
redirect('filters.cgi');
