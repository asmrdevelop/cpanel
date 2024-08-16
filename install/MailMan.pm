package Install::MailMan;

# cpanel - install/MailMan.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::Chkservd::Tiny  ();
use Cpanel::SafeRun::Simple ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    On dnsonly server, remove and disable mailman RPM
    On regular server perform some mailman maintenance & integrity tasks.

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

    $self->set_internal_name('mailman');

    return $self;
}

sub perform {
    my $self = shift;

    # mailman is installed after post install
    return if $ENV{'CPANEL_BASE_INSTALL'};

    # Suspend mailman monitoring
    Cpanel::Chkservd::Tiny::suspend_service( 'mailmanctl', 600 );

    return 1 if $self->dnsonly();

    my $path = '/usr/local/cpanel/bin';

    # more daily checks than install, mailman is installed via one RPM now
    my @commands = (
        "$path/checkmailmanrequests",
    );

    foreach my $cmd (@commands) {
        print Cpanel::SafeRun::Simple::saferun($cmd);
    }

    # Green light mailman now it's upgraded
    Cpanel::Chkservd::Tiny::resume_service('mailmanctl');

    return 1;
}

1;

__END__
