package Install::LocalPerl;

# cpanel - install/LocalPerl.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::ServerTasks ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Install modules perl-Try-Tiny and perl-HTTP-Tiny to the system perl.

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

    $self->set_internal_name('localperl');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub perform {
    my $self = shift;

    # Bootstrap /usr/bin/perl such that perlinstaller will function correctly
    Cpanel::ServerTasks::queue_task( ['PerlTasks'], 'install_locallib_loginprofile' );

    return 1;
}

1;

__END__
