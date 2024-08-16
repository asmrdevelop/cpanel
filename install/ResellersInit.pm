package Install::ResellersInit;    ## no critic(RequireFilenameMatchesPackage)

# cpanel - install/ResellersInit.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::FileUtils::Chown ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create resellers file /var/cpanel/resellers when missing

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('ResellersInit');

    return $self;
}

sub perform {
    my $self = shift;

    Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
        'uid'         => 0,
        'gid'         => 0,
        'octal_perms' => 0644,
        'path'        => $Cpanel::ConfigFiles::RESELLERS_FILE // $Cpanel::ConfigFiles::RESELLERS_FILE,    # avoid warning once
        'create'      => 1,
    );

    return 1;
}

1;

__END__
