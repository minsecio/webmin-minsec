# install_check.pl
# Called by Webmin to decide whether minsec is installed on this system.

use strict;
use warnings;
our %config;

# is_installed(mode)
# For mode 1, returns 2 if minsec is installed and has a config directory,
# 1 if only the binary is present, or 0 otherwise.
# For mode 0, returns 1 if the binary is present, 0 if not.
sub is_installed
{
	my ($mode) = @_;
	my $cmd = $config{'minsec_cmd'} || '/usr/bin/minsec';
	my $dir = $config{'config_dir'} || '/etc/minsec';
	return 0 if (!-x $cmd);
	return 1 if (!$mode);
	return -d $dir ? 2 : 1;
}

1;
