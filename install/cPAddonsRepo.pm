package Install::cPAddonsRepo;

# cpanel - install/cPAddonsRepo.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Task );

use Cpanel::Yum::Vars ();
use Cpanel::Repos     ();
use Cpanel::OS        ();

our $VERSION = '1.0';

=head1 NAME

Install::cPAddonsRepo

=head2 new()

Construct the Install::cPAddonsRepo task.

The constructor is compatible with the interface of Cpanel::Task (the parent class).

=cut

=head1 DESCRIPTION

  Enable the cPAddons repository to install cPaddons .

=over 1

=item Type: cPanel setup

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;

    $self->set_internal_name('cpaddon_repos');

    return $self;
}

=head2 perform()

Perform the YUM repo setup.

This method is compatible with the interface of Cpanel::Task (the parent class);

=cut

sub perform {
    my $self = shift;

    #
    # We skip this task on install since
    # yum vars are setup in installer already
    #
    # We do the cPAddons rpm install in the background as
    # to not disrupt the background yum processes that are
    # running during the fresh first time install
    #
    return 1 if $ENV{'CPANEL_BASE_INSTALL'};

    return 1 unless Cpanel::OS::supports_cpaddons();

    Cpanel::Yum::Vars::install();
    Cpanel::Repos->new()->install_repo( name => 'cPAddons' );

    return 1;
}

1;
