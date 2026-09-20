#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in, %text);
ReadParse();
minsec::require_acl('view');
my ($inspection, $inspect_error) = minsec::inspect();
my ($response, $response_error);
if (!$inspect_error) {
	($response, $response_error) = minsec::control_request({'cmd' => 'list'}, $inspection);
}
my $bans = $response ? ($response->{'bans'} || []) : [];
my ($page_bans, $page) = minsec::paginate($bans, $in{'page'}, minsec::settings()->{'perpage'});

ui_print_header('', $text{'bans_title'}, '', 'intro', 1, 1);
print minsec::navigation('bans');
print ui_alert_box(minsec::html_escape($inspect_error || $response_error), 'warning') if ($inspect_error || $response_error);
print ui_form_start('ban_action.cgi', 'post');
my @columns = (hlink($text{'bans_select'}, 'bans_select'), $text{'bans_address'}, $text{'bans_filter'}, $text{'bans_expires'});
my @rows;
foreach my $ban (@$page_bans) {
	my $address = minsec::html_escape($ban->{'net'} || '');
	push(@rows, [
		ui_checkbox('selected', $address, '', 0),
		$address,
		minsec::html_escape($ban->{'filter'} || ($ban->{'manual'} ? 'manual' : '-')),
		minsec::html_escape(minsec::format_duration($ban->{'expires_in'})),
	]);
}
print ui_columns_table(\@columns, undef, \@rows, undef, 0, undef, undef, 'bans');
if (minsec::check_acl('bans')) {
	print minsec::action_button($text{'bans_unban'}, 'operation', 'unban');
	print ui_table_start($text{'bans_manual'}, 'width=100%', 2);
	print ui_table_row(hlink($text{'bans_address'}, 'bans_address'), ui_textbox('network', '', 45));
	print ui_table_row(hlink($text{'bans_duration'}, 'bans_duration'), ui_textbox('duration', '', 12));
	print ui_table_row(hlink($text{'bans_filter'}, 'bans_filter'), ui_textbox('filter', 'manual', 24));
	print ui_table_end();
	print minsec::action_button($text{'bans_ban'}, 'operation', 'ban');
}
print ui_form_end();
ui_print_footer('index.cgi', $text{'index_dashboard'});
