package Install::IPAliases;

# cpanel - install/IPAliases.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

our $VERSION = '1.0';

=head1 DESCRIPTION

    update and enable ipaliases service (no start)
    then call scripts/rebuildippool

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

    $self->set_internal_name('ipaliases');

    return $self;
}

sub perform {
    my $self = shift;

    # Virtuozzo needs to have this as we inhert the ips rather than
    # adding them in WHM
    require Cpanel::IpPool;
    Cpanel::IpPool::rebuild();
    return 1;
}

1;

__END__
