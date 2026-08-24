#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in);
ReadParse();
minsec::require_post();
minsec::require_acl('bans');
my $operation = $in{'operation'} || '';
if ($operation eq 'ban') {
	my ($network, $network_error) = minsec::validate_network($in{'network'});
	error(minsec::html_escape($network_error)) if ($network_error);
	my ($duration, $duration_error) = minsec::validate_duration($in{'duration'}, 1);
	error(minsec::html_escape($duration_error)) if ($duration_error);
	my $filter = $in{'filter'} || 'manual';
	error('Invalid filter name') if ($filter !~ /\A[A-Za-z0-9_.-]+\z/);
	my $request = {'cmd' => 'ban', 'net' => $network, 'reason' => $filter};
	$request->{'ttl'} = $duration if (defined($duration));
	my (undef, $error) = minsec::control_request($request);
	error(minsec::html_escape($error)) if ($error);
	webmin_log('ban', 'network', $network, {'duration' => $duration, 'filter' => $filter});
}
elsif ($operation eq 'unban') {
	my @selected = split(/\0/, $in{'selected'} || '');
	error('No bans selected') if (!@selected);
	foreach my $candidate (@selected) {
		my ($network, $network_error) = minsec::validate_network($candidate);
		error(minsec::html_escape($network_error)) if ($network_error);
		my (undef, $error) = minsec::control_request({'cmd' => 'unban', 'net' => $network});
		error(minsec::html_escape($error)) if ($error);
		webmin_log('unban', 'network', $network);
	}
}
else {
	error('Invalid ban operation');
}
redirect('bans.cgi');
