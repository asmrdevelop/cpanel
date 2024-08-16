package Install::SUSetup;

# cpanel - install/SUSetup.pm                       Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use Cpanel::OS         ();
use Cpanel::SafetyBits ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Adjust owner and permissions of /bin/su

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

    $self->set_internal_name('susetup');

    return $self;
}

sub perform ($self) {

    Cpanel::SafetyBits::safe_chown( 'root', Cpanel::OS::sudoers(), '/bin/su' );
    chmod 04750, '/bin/su';

    return 1;
}

1;

__END__
