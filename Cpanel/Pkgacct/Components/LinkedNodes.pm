package Cpanel::Pkgacct::Components::LinkedNodes;

# cpanel - Cpanel/Pkgacct/Components/LinkedNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::LinkedNodes

=head1 DESCRIPTION

A pkgacct module to back up a user’s linked-node configuration
and remote home directories.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::Autodie                    ();
use Cpanel::DnsRoots::ErrorWarning     ();
use Cpanel::DNS::Unbound::Async        ();
use Cpanel::FileUtils::Write           ();
use Cpanel::JSON                       ();
use Cpanel::LinkedNode::Archive        ();
use Cpanel::LinkedNode::Worker::GetAll ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->perform()

See base class.

=cut

sub perform {
    my ($self) = @_;

    my $username = $self->get_user();
    my $work_dir = $self->get_work_dir();

    my $cpu = $self->get_cpuser_data();

    my %type_alias;

    my $dns;

    # Do nothing if there are no workers
    my @worker_hrs = Cpanel::LinkedNode::Worker::GetAll::get_all_from_cpuser($cpu) or return;

    my @promises;

    for my $worker_hr (@worker_hrs) {
        $dns ||= Cpanel::DNS::Unbound::Async->new();

        my ( $worker_type, $alias, $worker_conf ) = @{$worker_hr}{qw(worker_type  alias  configuration)};
        my $hostname = $worker_conf->hostname();

        my $ta_entry = $type_alias{$worker_type} = {
            alias    => $alias,
            hostname => $hostname,
        };

        push @promises, $dns->ask( $hostname, 'A' )->then(
            sub ($resp) {
                $ta_entry->{'ipv4'} = $resp->decoded_data();
            },
            Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher( $hostname, 'A' ),
        );

        push @promises, $dns->ask( $hostname, 'AAAA' )->then(
            sub ($resp) {
                $ta_entry->{'ipv6'} = $resp->decoded_data();
            },
            Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher( $hostname, 'AAAA' ),
        );
    }

    # Wait for all queries to resolve.
    my $cv = AnyEvent->condvar();
    Promise::ES6->all( \@promises )->then($cv);
    $cv->recv();

    for my $worker_hr (@worker_hrs) {
        my ( $alias, $token, $worker_conf ) = @{$worker_hr}{qw(alias  api_token  configuration)};

        my $worker_pkgacct_reldir = _build_worker_pkgacct_parent_dir( $work_dir, $alias );

        # We put the archive one-deeper here so that the restore process can
        # tar the directory itself over to the worker node’s /home*. We could
        # alternatively teach TarRestore.pm to create a directory beforehand,
        # but this is a bit simpler.
        #
        my $worker_pkgacct_dir = "$work_dir/$worker_pkgacct_reldir";

        if ( Cpanel::Autodie::mkdir_if_not_exists($worker_pkgacct_dir) ) {
            _stream_pkgacct_to( $alias, $username, $worker_pkgacct_dir );
        }

    }

    if (%type_alias) {

        # Canonical dump makes this easier to test.
        Cpanel::FileUtils::Write::write(
            "$work_dir/worker_nodes.json",
            Cpanel::JSON::canonical_dump( \%type_alias ),
        );
    }

    return;
}

sub _build_worker_pkgacct_parent_dir ( $work_dir, $alias ) {
    my $worker_pkgacct_reldir = Cpanel::LinkedNode::Archive::subarchive_relative_root($alias);

    # This all is now a bit “over-engineered” but made sense for the
    # original subarchive_relative_root() function, which returned
    # a longer filesystem path.
    my @pieces = split m</>, $worker_pkgacct_reldir;

    for my $i ( 0 .. ( $#pieces - 1 ) ) {
        my $cur_relpath = join( '/', @pieces[ 0 .. $i ] );
        Cpanel::Autodie::mkdir_if_not_exists("$work_dir/$cur_relpath");
    }

    return $worker_pkgacct_reldir;
}

sub _stream_pkgacct_to {

    my ( $worker_alias, $username, $worker_work_dir ) = @_;

    require Cpanel::LinkedNode::Worker::WHM::Pkgacct;
    my $remote_pkgacct_dir = Cpanel::LinkedNode::Worker::WHM::Pkgacct::execute_pkgacct_for_user( $worker_alias, $username );

    require Cpanel::LinkedNode;
    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( 'alias' => $worker_alias );

    require Cpanel::LinkedNode::Convert::ArchiveDirFromNode;
    Cpanel::LinkedNode::Convert::ArchiveDirFromNode::receive(
        node_obj         => $node_obj,
        archive_dir_path => $worker_work_dir,
        remote_dir_path  => $remote_pkgacct_dir,
    );

    return;
}

1;
