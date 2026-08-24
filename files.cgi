#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%text);
minsec::require_acl('raw');
my ($inspection, $error) = minsec::inspect();
ui_print_header('', $text{'files_title'}, '', 'intro', 1, 1);
print minsec::navigation('files');
print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
my @rows;
if ($inspection) {
	foreach my $path (minsec::discovered_files($inspection)) {
		my $encoded = urlize($path);
		push(@rows, [
			minsec::html_escape($path),
			'<a href="file_edit.cgi?path='.$encoded.'">'.minsec::html_escape($text{'files_edit'}).'</a>',
		]);
	}
}
print ui_columns_table(['File', ''], undef, \@rows);
print ui_links_row([
	minsec::link_html('file_edit.cgi?new=1&type=dropin', $text{'files_create_dropin'}),
	minsec::link_html('file_edit.cgi?new=1&type=filter', $text{'files_create_filter'}),
]);
ui_print_footer('index.cgi', $text{'index_dashboard'});
