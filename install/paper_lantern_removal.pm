package Install::paper_lantern_removal;

# cpanel - install/paper_lantern_removal.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::SafeDir::RM ();

our $VERSION = '1.0';

=head1 NAME

Install::paper_lantern_removal - removal of paper_lantern

=head1 DESCRIPTION

This module removes file structure for the deprecated paper_lantern theme.

=over 1

=item Type: Sanity

=item Frequency: once

=item EOL: never

=back

=head1 METHODS

=over

=item new()

Constructor for Install::paper_lantern_removal objects.

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('110_paper_lantern_removal');

    return $self;
}

=item perform()

Method to do actual work of the Install::paper_lantern_removal task.

=over

=item *

Removes paper_lantern directory and its contents from ulc.

=back

=cut

our $pl_dir;

sub perform {
    my $self = shift;

    my $status = 1;
    $self->do_once(
        version => '110-paper-lantern-removal',
        eol     => 'never',
        code    => sub {
            $status = $self->_remove_paper_lantern();
        }
    );

    return $status;
}

sub _remove_paper_lantern {
    my $self = shift;

    $pl_dir ||= '/usr/local/cpanel/base/frontend/paper_lantern';

    Cpanel::SafeDir::RM::safermdir($pl_dir);
    if ( -e $pl_dir ) {
        warn "Failed to remove $pl_dir: $!";
        return 0;
    }
    return 1;
}

=back

=cut

1;
