#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%config, $restore_was_running);

sub backup_config_files
{
	return ($config{'config_dir'} || '/etc/minsec');
}

sub pre_backup
{
	return;
}

sub post_backup
{
	return;
}

sub pre_restore
{
	$restore_was_running = minsec::service_state()->{'running'};
	return;
}

sub post_restore
{
	my ($check, $error) = minsec::check_config($config{'config_dir'} || '/etc/minsec');
	return $error if ($error);
	return $check->{'error'} || 'Restored minsec configuration is invalid' if (!$check->{'ok'});
	if ($restore_was_running) {
		my ($ok, $restart_error) = minsec::service_action('restart');
		return $restart_error || 'Unable to restart minsec' if (!$ok);
	}
	return;
}

1;
