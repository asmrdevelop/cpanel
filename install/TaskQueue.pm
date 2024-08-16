package Install::TaskQueue;

# cpanel - install/TaskQueue.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::SafeRun::Object ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Ensures that queueprocd is set up and restarted so that tasks can be queued.

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

    $self->set_internal_name('taskqueue');

    # cpanelservice ensures that new service init configuration for queueprocd is installed before restart.
    $self->add_dependencies(qw( cpanelservice ));

    return $self;
}

sub perform {
    my $self = shift;

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        print "Restarting queueprocd\n";
        Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/restartsrv_queueprocd' );
    }

    return 1;
}

1;

__END__
