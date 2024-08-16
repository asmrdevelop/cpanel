#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/wpt.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::wpt;

=encoding utf8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::wpt

=head1 SYNOPSIS

use Cpanel::AdminBin::Call ();
Cpanel::AdminBin::Call::call( "Cpanel", "wpt", "install" );
Cpanel::AdminBin::Call::call( "Cpanel", "wpt", "install_status" );

=head1 DESCRIPTION

This admin bin provides a route for installing a Wordpress site on a domain and polling the status of the process.

=cut

use strict;
use warnings;

use Cpanel ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::ServerTasks       ();
use Cpanel::TaskQueue::Reader ();
use Cpanel::WPTK::Site        ();

use parent ('Cpanel::Admin::Base');

use constant _actions => (
    'install',
    'install_status',
);

=head1 FUNCTIONS

=head2 install

Queues a task that installs Wordpress on the user's docroot.
It will only do this if the target path is empty.

=cut

sub install {
    my ($self) = @_;

    my $user = $self->get_caller_username();
    Cpanel::initcp($user);
    local $Cpanel::homedir = $self->get_cpuser_homedir();

    unless ( Cpanel::WPTK::Site::can_install() ) {
        return 0, lh()->maketext('Can not install. Please check that WordPress is installed and target directory is empty.');
    }

    my $domain = $Cpanel::CPDATA{'DNS'};

    Cpanel::ServerTasks::queue_task( ['WPTK'], "wordpress_install_on_domain $user $domain" );
    return 1, lh()->maketext('The system has queued a task to install the WordPress site.');
}

=head2 install_status

Returns the status of a running or completed Wordpress install task.

=cut

sub install_status {
    my ( $self, @args ) = @_;

    my $user = $self->get_caller_username();
    Cpanel::initcp($user);
    my $domain = $Cpanel::CPDATA{'DNS'};

    my ( $status, $msg ) = _is_install_queued( $user, $domain );
    return $status, $msg;
}

sub _is_install_queued {
    my ( $user, $domain ) = @_;

    my $queue_hr     = Cpanel::TaskQueue::Reader::read_queue();
    my @running_jobs = grep { $_->{'_command'} eq 'wordpress_install_on_domain' && $_->{'_args'}->[0] eq $user && $_->{'_args'}->[1] eq $domain } @{ $queue_hr->{'processing_queue'} };
    if ( scalar @running_jobs ) {
        return 'in progress', lh()->maketext('Installation is in progress.');
    }

    my @waiting_jobs = grep { $_->{'_command'} eq 'wordpress_install_on_domain' && $_->{'_args'}->[0] eq $user && $_->{'_args'}->[1] eq $domain } @{ $queue_hr->{'waiting_queue'} };
    if ( scalar @waiting_jobs ) {
        return 'queued', lh()->maketext('Installation has been queued.');
    }

    return 'not queued', "Not in queue";
}

1;
