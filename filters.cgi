#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%text);
minsec::require_acl('view');
my ($inspection, $error) = minsec::inspect();
my $filters = $inspection ? ($inspection->{'filters'} || []) : [];

ui_print_header('', $text{'filters_title'}, '', 'intro', 1, 1);
print minsec::navigation('filters');
print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
my @columns = ($text{'filters_name'}, $text{'filters_type'}, $text{'filters_source'}, $text{'filters_enabled'}, $text{'filters_policy'}, '');
my @rows;
foreach my $filter (@$filters) {
	my $policy = $filter->{'effective_policy'} || {};
	my @policy = map { minsec::html_escape($_.'='.$policy->{$_}) } sort(keys(%$policy));
	push(@rows, [
		minsec::html_escape($filter->{'name'}),
		minsec::html_escape($filter->{'builtin'} ? 'built-in' : 'custom'),
		minsec::html_escape($filter->{'source'} || '-'),
		$filter->{'enabled'} ? ($text{'yes'} || 'Yes') : ($text{'no'} || 'No'),
		join('<br>', @policy) || '-',
		minsec::check_acl('filters') ? minsec::link_html('filter_edit.cgi?name='.main::urlize($filter->{'name'}), 'Edit policy') : '',
	]);
}
print ui_columns_table(\@columns, undef, \@rows);
if (minsec::check_acl('filters')) {
	print ui_links_row([
		minsec::link_html('file_edit.cgi?new=1&type=filter', $text{'files_create'}),
	]);
}
ui_print_footer('index.cgi', $text{'index_dashboard'});
