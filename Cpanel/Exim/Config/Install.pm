package Cpanel::Exim::Config::Install;

# cpanel - Cpanel/Exim/Config/Install.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Dir::Loader      ();
use Whostmgr::Exim::Config   ();
use Cpanel::StringFunc::Trim ();

sub install_exim_configuration_from_dry_run {
    my $acls_to_install_ref = shift;
    my @ACLS_TO_INSTALL;

    if ( ref $acls_to_install_ref ) {
        @ACLS_TO_INSTALL = @{$acls_to_install_ref};
    }
    else {
        my %ACLBLOCKS = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/etc/exim/acls');

        foreach my $aclblock ( sort keys %ACLBLOCKS ) {
            foreach my $file ( grep { $_ =~ /\.dry_run$/ } @{ $ACLBLOCKS{$aclblock} } ) {
                $file = Cpanel::StringFunc::Trim::endtrim( $file, '.dry_run' );
                push @ACLS_TO_INSTALL, "$aclblock/$file";
            }
        }
    }

    return Whostmgr::Exim::Config::attempt_exim_config_update(
        'files'           => [ 'local', 'localopts', 'localopts.shadow' ],
        'acl_dry_run'     => 1,
        'acls_to_install' => \@ACLS_TO_INSTALL,
    );
}

1;
