#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in);
ReadParse();
minsec::require_post();
minsec::require_acl('config');
my %defaults;
foreach my $field (['ban_duration', 'bantime'], ['find_time', 'findtime']) {
	my ($seconds, $duration_error) = minsec::validate_duration($in{$field->[0]}, 1);
	error(minsec::html_escape($duration_error)) if ($duration_error);
	$defaults{$field->[1]} = $seconds.'s' if (defined($seconds));
}
if (defined($in{'max_retries'}) && $in{'max_retries'} ne '') {
	error('Max retries must be a positive integer') if ($in{'max_retries'} !~ /^\d+$/ || !$in{'max_retries'});
	$defaults{'maxretry'} = int($in{'max_retries'});
}
my @allowlist;
foreach my $line (split(/\r?\n/, $in{'allowlist'} || '')) {
	next if ($line =~ /^\s*$/);
	$line =~ s/^\s+|\s+$//g;
	my ($network, $network_error) = minsec::validate_network($line);
	error(minsec::html_escape($network_error)) if ($network_error);
	push(@allowlist, $network);
}
my $values = {
	'defaults' => {
		%defaults,
		'escalate_enabled' => $in{'escalation_enabled'} ? 'true' : 'false',
		'backend' => $in{'backend'},
	},
	'allowlist' => \@allowlist,
	'escalate' => {'factor' => $in{'escalation_multiplier'}},
	'paths' => {'socket' => $in{'socket'}, 'state_dir' => $in{'state_dir'}},
};
my $content = minsec::render_webmin_toml($values);
my ($inspection, $inspect_error) = minsec::inspect();
error(minsec::html_escape($inspect_error)) if ($inspect_error);
my $config_dir = minsec::inspection_path($inspection, 'config_dir') || minsec::settings()->{'config_dir'};
my $path = "$config_dir/conf.d/webmin.toml";
my ($safe_path, $path_error) = minsec::allowed_file_path($path, $inspection, 1, 'dropin');
error(minsec::html_escape($path_error)) if ($path_error);
my (undef, $save_error) = minsec::staged_change('config_dir' => $config_dir, 'path' => $safe_path, 'content' => $content);
error(minsec::html_escape($save_error)) if ($save_error);
webmin_log('save', 'config', $safe_path);
if (($in{'save'} || '') eq 'restart') {
	minsec::require_acl('service');
	my ($ok, $restart_error) = minsec::service_action('restart');
	error(minsec::html_escape($restart_error)) if (!$ok);
	webmin_log('restart', 'service', minsec::settings()->{'service_name'});
}
redirect('config.cgi');
