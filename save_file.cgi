#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in);
ReadParse();
minsec::require_post();
minsec::require_acl('raw');
my ($inspection, $inspect_error) = minsec::inspect();
error(minsec::html_escape($inspect_error)) if ($inspect_error);
my $config_dir = minsec::inspection_path($inspection, 'config_dir') || minsec::settings()->{'config_dir'};
my $type = $in{'type'} && $in{'type'} eq 'filter' ? 'filter' : 'dropin';
my $path = $in{'path'} || '';
if ($in{'new'}) {
	my ($name, $name_error) = minsec::validate_filename($in{'name'}, $type);
	error(minsec::html_escape($name_error)) if ($name_error);
	$path = "$config_dir/".($type eq 'filter' ? 'filters' : 'conf.d')."/$name";
}
my ($safe_path, $path_error) = minsec::allowed_file_path($path, $inspection, $in{'new'} ? 1 : 0, $type);
error(minsec::html_escape($path_error)) if ($path_error);
my $operation = $in{'operation'} || 'save';
error('Cannot delete the main configuration file') if ($operation eq 'delete' && $safe_path eq (minsec::main_config_file($inspection) || ''));
my %change = ('config_dir' => $config_dir, 'path' => $safe_path);
if ($operation eq 'delete') {
	$change{'delete'} = 1;
}
else {
	$change{'content'} = $in{'content'} // '';
}
my (undef, $save_error) = minsec::staged_change(%change);
error(minsec::html_escape($save_error)) if ($save_error);
webmin_log($operation eq 'delete' ? 'delete' : ($in{'new'} ? 'create' : 'save'), 'file', $safe_path);
if ($operation eq 'restart') {
	minsec::require_acl('service');
	my ($ok, $restart_error) = minsec::service_action('restart');
	error(minsec::html_escape($restart_error)) if (!$ok);
}
redirect('files.cgi');
