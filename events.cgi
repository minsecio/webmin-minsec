#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in, %text);
ReadParse();
minsec::require_acl('events');
my ($events, $error) = minsec::read_events($in{'last'} || minsec::settings()->{'perpage'});
ui_print_header('', $text{'events_title'}, '', 'intro', 1, 1);
print minsec::navigation('events');
print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
my @columns = qw(Time Event Address Filter Hits TTL Details);
my @rows;
foreach my $event (@{$events || []}) {
	push(@rows, [
		minsec::html_escape(minsec::format_timestamp($event->{'ts'})),
		minsec::html_escape($event->{'kind'} || '-'),
		minsec::html_escape($event->{'net'} || '-'),
		minsec::html_escape($event->{'filter'} || '-'),
		minsec::html_escape($event->{'hits'} // '-'),
		minsec::html_escape(minsec::format_duration($event->{'ttl'})),
		minsec::html_escape($event->{'manual'} ? 'manual' : ($event->{'escalation'} || 0) > 1 ? 'escalated' : ''),
	]);
}
print ui_columns_table(\@columns, undef, \@rows);
ui_print_footer('index.cgi', $text{'index_dashboard'});
