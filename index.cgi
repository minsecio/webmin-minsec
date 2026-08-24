#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%text);

minsec::require_acl('view');
my $service = minsec::service_state();
my ($inspection, $inspect_error) = minsec::inspect();
my ($status, $status_error);
if (!$inspect_error && $service->{'running'}) {
	($status, $status_error) = minsec::control_request({'cmd' => 'status'}, $inspection);
}

ui_print_header('', $text{'index_title'}, '', 'intro', 1, 1);
print minsec::navigation('dashboard');

my $state = $service->{'running'} ? $text{'index_running'} :
	$service->{'known'} ? $text{'index_stopped'} : $text{'index_unknown'};
my @rows = (
	[ $text{'index_service'}, minsec::html_escape($state) ],
	[ $text{'index_boot'}, $service->{'boot'} ? $text{'yes'} : $text{'no'} ],
);
if ($inspection) {
	push(@rows,
		[ $text{'index_version'}, minsec::html_escape($inspection->{'version'} || '-') ],
		[ $text{'index_backend'}, minsec::html_escape($inspection->{'effective'}->{'defaults'}->{'backend'} || '-') ]);
}
if ($status) {
	my $metrics = $status->{'status'} || $status;
	push(@rows,
		[ $text{'index_uptime'}, minsec::format_duration($metrics->{'uptime'}) ],
		[ $text{'index_lines'}, minsec::html_escape($metrics->{'lines'} // 0) ],
		[ $text{'index_attackers'}, minsec::html_escape($metrics->{'tracked'} // 0) ],
		[ $text{'index_bans_total'}, minsec::html_escape($metrics->{'bans_total'} // 0) ],
		[ $text{'index_bans_active'}, minsec::html_escape($metrics->{'active_bans'} // 0) ]);
	if (ref($metrics->{'filters'}) eq 'ARRAY' && @{$metrics->{'filters'}}) {
		my @filter_rows;
		foreach my $filter (@{$metrics->{'filters'}}) {
			push(@filter_rows, [
				minsec::html_escape($filter->{'name'} || '-'),
				minsec::html_escape($filter->{'matched'} // 0),
				minsec::html_escape($filter->{'banned'} // 0),
				minsec::html_escape($filter->{'maxretry'} // 0),
			]);
		}
		$metrics->{'filter_rows'} = \@filter_rows;
	}
}
print ui_table_start($text{'index_dashboard'}, 'width=100%', 2);
foreach my $row (@rows) {
	print ui_table_row($row->[0], $row->[1]);
}
print ui_table_end();
if ($status && ref(($status->{'status'} || $status)->{'filter_rows'}) eq 'ARRAY') {
	print ui_columns_table(['Filter', 'Matched', 'Banned', 'Max retries'], undef,
		($status->{'status'} || $status)->{'filter_rows'});
}

foreach my $error ($inspect_error, $status_error) {
	print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
}

if (minsec::check_acl('service') || minsec::check_acl('boot')) {
	print ui_form_start('service_action.cgi', 'post');
	print ui_table_start($text{'index_actions'}, 'width=100%', 2);
	if (minsec::check_acl('service')) {
		my @buttons = $service->{'running'} ?
			([ 'restart', $text{'index_restart'} ], [ 'stop', $text{'index_stop'} ]) :
			([ 'start', $text{'index_start'} ]);
		my $html = join(' ', map { minsec::action_button($_->[1], 'action', $_->[0]) } @buttons);
		print ui_table_row($text{'index_service'}, $html);
	}
	if (minsec::check_acl('boot')) {
		my $action = $service->{'boot'} ? 'disable' : 'enable';
		my $label = $service->{'boot'} ? $text{'index_disable'} : $text{'index_enable'};
		print ui_table_row($text{'index_boot'}, minsec::action_button($label, 'action', $action));
	}
	print ui_table_end();
	print ui_form_end();
}

ui_print_footer('/', $text{'index'});
