package Install::RemoveGlobalEventImportance;

# cpanel - install/RemoveGlobalEventImportance.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );
use strict;
use warnings;

our $VERSION = '1.0';

=head1 DESCRIPTION

    Remove importance references from the ChangePassword
    events 'ResetRequest' and 'NewUser'.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

use Cpanel::iContact::EventImportance::Writer ();

my @EVENTS = (
    { app => 'ChangePassword', event => 'ResetRequest' },
    { app => 'ChangePassword', event => 'NewUser' },
);

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;

    $self->set_internal_name('remove-global-event-importance');

    return $self;
}

sub perform {
    my $self = shift;

    my $writer = Cpanel::iContact::EventImportance::Writer->new();
    foreach my $event (@EVENTS) {
        $writer->unset_event_importance( $event->{app}, $event->{event} );
    }
    my ( $ok, $err ) = $writer->save_and_close();
    die $err if !$ok;

    return;
}

1;
