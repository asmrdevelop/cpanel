package Install::PackageExtension;    ## no critic(RequireFilenameMatchesPackage)

# cpanel - install/PackageExtension.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Whostmgr::Packages::Load ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Check that no packages are named 'extensions' as this is a reserved
    keyword for package extensions.

    If so rename the package 'extension' to a unique name
    and notify the customer.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('package_extension');

    return $self;
}

sub perform {
    my $self = shift;

    my $package_extensions_dir = Whostmgr::Packages::Load::package_extensions_dir();
    $package_extensions_dir =~ s{/+$}{};
    if ( -f $package_extensions_dir ) {
        require Whostmgr::Packages;
        my $destination = "extensions.package.$$." . time;
        Whostmgr::Packages::rename_package( 'extensions', $destination ) || return;    # rename_package() already does errors
        $self->notify($destination);

    }

    return 1;
}

sub notify {
    my ( $self, $package_destination ) = @_;
    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Install::PackageExtension',
        'application'      => 'Install::PackageExtension',
        'constructor_args' => [
            origin              => 'install',
            package_destination => $package_destination,
        ]
    );
}

1;
