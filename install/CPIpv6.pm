package Install::CPIpv6;

# cpanel - install/CPIpv6.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::Init::Simple ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    - update user data cache if required
    - install and enable cpipv6 service

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

    $self->set_internal_name('CPIpv6');

    return $self;
}

sub perform {
    my $self = shift;
    Cpanel::Init::Simple::call_cpservice_with( 'cpipv6' => qw/install enable/ );
    return 1;
}

1;

__END__
