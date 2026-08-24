use strict;
use warnings;
no warnings 'redefine';

require 'minsec/minsec-lib.pl'; ## no critic
our (%text, %in);

sub acl_security_form
{
	my ($options) = @_;
	foreach my $permission (minsec::acl_permissions()) {
		my $label = $text{'acl_'.$permission} || $permission;
		print ui_table_row($label,
			ui_yesno_radio($permission, $options->{$permission}));
	}
}

sub acl_security_save
{
	my ($options) = @_;
	foreach my $permission (minsec::acl_permissions()) {
		$options->{$permission} = $in{$permission} ? 1 : 0;
	}
}

