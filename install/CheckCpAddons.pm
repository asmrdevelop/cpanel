package Install::CheckCpAddons;

# cpanel - install/CheckCpAddons.pm                Copyright 2021 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use cPstrict;

use Cpanel::OS                   ();
use Cpanel::FileUtils::TouchFile ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Check if cPaddons are used or not and touch a file to disable
    the cPaddons when no addons are currently installed on the server.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

We should remove it once we deprecate cPAddons.

=back

=cut

use constant DISABLE_FILE => q[/var/cpanel/cpaddons.disabled];

exit __PACKAGE__->runtask() unless caller;

sub new ($proto) {

    my $self = $proto->SUPER::new;
    $self->set_internal_name('check_cpaddons');

    return $self;
}

sub perform ($self) {

    my $is_enabled;

    if ( Cpanel::OS::supports_cpaddons() ) {
        my $has_cpaddons = eval {
            require Whostmgr::Cpaddon;
            Whostmgr::Cpaddon::has_some_addons_installed();
        };

        $is_enabled = 1 if $has_cpaddons;
    }
    else {
        # we cannot disable cpaddons by default without an alternate
        #   solution to install WHMCS
        Cpanel::FileUtils::TouchFile::touchfile(DISABLE_FILE);
    }

    unlink DISABLE_FILE if $is_enabled;

    return 1;
}

1;
