package Cpanel::LinkedNode::Convert::FromDistributed::Mail;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail

=head1 DESCRIPTION

This module implements most parts of the logic to convert a user whose mail
is on a child node to delegate its mail to the local server.

=cut

# Handy one-liners for testing:
#
# Regular conversion:
# REMOTE_USER=root perl -MCpanel::Output::Formatted::Terminal -MCpanel::LinkedNode::Convert::FromDistributed::Mail -e'Whostmgr::ACLS::init_acls(); Cpanel::LinkedNode::Convert::FromDistributed::Mail::convert( username => "dist1", output_obj => Cpanel::Output::Formatted::Terminal->new() )'
#
# Local, “forced” conversion:
# REMOTE_USER=root perl -MCpanel::DnsUtils::Batch -MCpanel::Output::Formatted::Terminal -MCpanel::LinkedNode::Convert::FromDistributed::Mail -e'Whostmgr::ACLS::init_acls(); my $dns_ar = Cpanel::LinkedNode::Convert::FromDistributed::Mail::local_convert( username => "dist1", output_obj => Cpanel::Output::Formatted::Terminal->new() ); print "Updating DNS …\n"; Cpanel::DnsUtils::Batch::set($dns_ar);'

use Cpanel::Imports;

use File::Temp ();

use Cpanel::Autodie qw(mkdir_if_not_exists rmdir_if_exists);

use Cpanel::Config::CpUserGuard                                 ();
use Cpanel::Email::Perms::User                                  ();
use Cpanel::Exception                                           ();
use Cpanel::Filesys::Home                                       ();
use Cpanel::LinkedNode::AccountCache                            ();
use Cpanel::LinkedNode::Convert::Common::Child                  ();
use Cpanel::LinkedNode::Convert::Common::FromRemote             ();
use Cpanel::LinkedNode::Convert::Common::Mail::DNS              ();
use Cpanel::LinkedNode::Convert::Common::Mail::FromRemote       ();
use Cpanel::LinkedNode::Convert::FromDistributed::Mail          ();
use Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend ();
use Cpanel::LinkedNode::Convert::FromDistributed::Mail::DNS     ();
use Cpanel::LinkedNode::Convert::FromDistributed::Mail::State   ();
use Cpanel::LinkedNode::Convert::FromDistributed::Mail::Sync    ();
use Cpanel::LinkedNode::Convert::ArchiveDirFromNode             ();
use Cpanel::LinkedNode::Convert::TaskRunner                     ();
use Cpanel::LinkedNode::Worker::Storage                         ();
use Cpanel::NAT                                                 ();
use Cpanel::Output::Restore::Translator                         ();
use Cpanel::PromiseUtils                                        ();
use Cpanel::PwCache                                             ();
use Cpanel::UserLock                                            ();
use Cpanel::Validate::IP                                        ();
use Cpanel::Validate::IP::v4                                    ();
use Whostmgr::Accounts::List                                    ();

our @_DISABLED_RESTOREPKG_MODULES = qw(
  Account
  APITokens
  AuthnLinks
  BandwidthData
  DNSSEC
  ZoneFile
  Ftp
  Homedir
  LinkedNodes
  Logs
  Reseller
  Shell
  VhostIncludes
);

=head1 FUNCTIONS

=head2 convert( %OPTS )

Converts an existing account whose mail is remote to retrieve offloaded mail to
the local server.

%OPTS are:

=over

=item * C<username> - The account’s username.

=item * C<output_obj> - A L<Cpanel::Output> instance that will receive
notifications while this conversion is in process.

=back

Returns nothing.

=cut

sub convert (@opts_kv) {
    return _convert_or_restore(
        [qw( username output_obj )],
        @opts_kv,
    );
}

=head2 $dns_updates_ar = local_convert( %OPTS )

The same as C<convert()> but does not reach out to the remote node.

This effectively “forgets” the child account and forces all service
to be hosted locally. All MX records will point to the local server.
No mail is synced from the (former) child node.

%OPTS are the same, but the return is different. Because this function
is expected to run in a context that dedistributes many accounts at
a time, DNS changes are deferred; the return value is a reference to
an array of arrayrefs, suitable to give to L<Cpanel::DnsUtils::Batch>’s
C<set()> function.

=cut

sub local_convert (@opts_kv) {
    my $dns_update_ar = _convert_or_restore(
        [qw( username output_obj )],
        @opts_kv,
        local_components_only => 1,
        defer                 => ['dns'],
    );

    return $dns_update_ar || [];
}

sub _convert_or_restore ( $req_ar, %opts ) {
    my @missing = grep { !length $opts{$_} } @$req_ar;
    die "need: @missing" if @missing;

    my %input = %opts{@$req_ar};

    my $user_lock = Cpanel::UserLock::create_shared_or_die( $input{'username'} );

    my @things_to_defer = $opts{'defer'} ? @{ $opts{'defer'} } : ();

    my $local_components_only = length $opts{local_components_only};

    my $state = Cpanel::LinkedNode::Convert::FromDistributed::Mail::State->new();
    $state->set(
        defer_dns => scalar( grep { $_ eq 'dns' } @things_to_defer ),

        # When true this tells the DNS-update layer that all mail-related
        # records should point to local server, regardless of
        # which IPs might actually exist on the remote node.
        always_matches_ip_addr => !!$local_components_only,

        deferred => {},
    );

    my @main_steps = (
        {
            label => locale()->maketext('Retrieving child node settings …'),
            code  => \&_load_linked_node,
        },
    );

    if ( !$local_components_only ) {
        push @main_steps, (
            {
                label => locale()->maketext('Retrieving child node network settings …'),
                code  => \&_get_child_node_network_settings,
            },
        );
    }

    push @main_steps, (
        {
            label => locale()->maketext('Checking for any required [asis,DNS] updates …'),
            code  => \&_determine_dns_updates,
        },
    );

    if ( !$local_components_only ) {
        push @main_steps, (
            {
                label => locale()->maketext('Creating the remote mail-only archive …'),
                code  => \&Cpanel::LinkedNode::Convert::Common::FromRemote::step__pkgacct_on_source,
            },
            {
                label      => locale()->maketext('Copying the account archive from the child node …'),
                code       => \&_copy_archive,
                undo       => \&_delete_local_archive,
                undo_label => sub {
                    if ( $state->get('target_archive_deleted') ) {
                        return undef;
                    }

                    return locale()->maketext('Deleting the account archive from the local server …');
                },
            },
            {
                label => locale()->maketext('Deleting the account archive from the child node …'),
                code  => \&_delete_source_account_archives,
            },
            {
                label => locale()->maketext('Restoring the account on the local server …'),
                code  => \&_local_restore,
            },
            {
                label => locale()->maketext('Copying the mail-related home directory items from the child node …'),
                code  => \&_retrieve_mail_parts_of_homedir,
            }
        );
    }

    push @main_steps, (
        {
            label => locale()->maketext('Normalizing email configuration on the local server …'),
            code  => \&_local_normalize_email,
        },
        {
            label      => locale()->maketext('Removing local direct mail routing …'),
            code       => \&Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend::step__remove_manual_mx,
            undo       => \&Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend::undo__remove_manual_mx,
            undo_label => locale()->maketext('Restoring local direct mail routing …'),
        },
        {
            label      => locale()->maketext('Updating account configuration …'),
            code       => \&_unset_worker_node,
            undo       => \&_restore_worker_node,
            undo_label => locale()->maketext('Undoing account configuration updates …')
        },
    );

    if ( $state->get('defer_dns') ) {
        push @main_steps, (
            {
                label => locale()->maketext('Determining necessary [asis,DNS] updates …'),
                code  => sub ( $input_hr, $state_obj ) {
                    my $deferred_ar = _update_dns( $input_hr, $state_obj );

                    my $deferred_hr = $state_obj->get('deferred');

                    push @{ $deferred_hr->{'dns'} }, @$deferred_ar;
                },
            },
        );
    }
    else {
        push @main_steps, (
            {
                label      => locale()->maketext('Updating [asis,DNS] …'),
                code       => \&_update_dns,
                undo       => \&_restore_dns,
                undo_label => locale()->maketext('Undoing [asis,DNS] updates …'),
            },
        );
    }

    push @main_steps, (
        {
            label      => locale()->maketext('Updating caches …'),
            code       => \&_remove_from_linked_node_cache,
            undo       => \&_restore_to_linked_node_cache,
            undo_label => locale()->maketext('Undoing cache updates …')
        },
    );

    if ( !$local_components_only ) {

        # At this point all relevant DNS updates and configuration updates should be complete. It should
        # be safe to set up the proxying from the child to the parent (local server) and the manual MX
        # redirects to make sure Exim doesn’t have any caching issues.
        push @main_steps, (
            {
                label      => locale()->maketext('Setting up service proxying on the child node …'),
                code       => \&Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend::step__set_up_source_service_proxy,
                undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::undo__set_up_source_service_proxy,
                undo_label => locale()->maketext('Reverting service proxying setup on the child node …'),
            },
            {
                label => locale()->maketext('Terminating remote mail connections …'),
                code  => \&_kick_source_connections,
            },
            {
                label      => locale()->maketext('Setting up direct mail routing on the child node …'),
                code       => \&Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend::step__set_up_source_manual_mx,
                undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::undo__set_up_source_manual_mx,
                undo_label => locale->maketext('Reverting direct mail routing setup on the child node …'),
            },
            {
                label => locale()->maketext('Synchronizing mail …'),
                code  => \&_sync_mail,
            },
            {
                label => locale()->maketext('Reconfiguring the child node’s account …'),
                code  => \&_unchildify_former_child_account,
            },
        );
    }

    Cpanel::LinkedNode::Convert::TaskRunner->run(
        $opts{'output_obj'},
        \@main_steps,
        \%input,
        $state,
    );

    if ( $state->get('defer_dns') ) {
        $opts{'output_obj'}->info( locale()->maketext( 'Conversion of the account “[_1]” will complete once [asis,DNS] updates occur.', $opts{'username'} ) );
    }
    else {
        $opts{'output_obj'}->success( locale()->maketext( 'Conversion of the account “[_1]” succeeded.', $opts{'username'} ) );
    }

    my $deferred_hr = $state->get('deferred');

    return @{$deferred_hr}{@things_to_defer};
}

sub _delete_source_account_archives ( $input_hr, $state_obj ) {
    my $p = Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::delete_source_account_archives_p( $input_hr, $state_obj );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _unchildify_former_child_account ( $input_hr, $state_obj ) {
    my $p = Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::unchildify_former_child_account_p( $input_hr, $state_obj );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _sync_mail ( $input_hr, $state_obj ) {
    my $node_obj = $state_obj->get('source_node_obj');

    my $indent = $input_hr->{'output_obj'}->create_indent_guard();

    Cpanel::LinkedNode::Convert::FromDistributed::Mail::Sync::sync(
        %{$input_hr}{ 'username', 'output_obj' },

        hostname  => $node_obj->hostname(),
        api_token => $node_obj->api_token(),
    );

    return;
}

sub _load_linked_node ( $input_hr, $state_obj ) {

    my $node_obj = Cpanel::LinkedNode::Convert::Common::FromRemote::get_source_node_obj(
        $input_hr->{'username'},
        'Mail',
    );

    $state_obj->set( source_node_obj => $node_obj );

    return;
}

sub _get_child_node_network_settings ( $input_hr, $state_obj ) {

    my $network_p = Cpanel::LinkedNode::Convert::Common::Child::get_network_setup_p(
        $state_obj->get('source_node_obj'),
    );

    my $network_ar = Cpanel::PromiseUtils::wait_anyevent($network_p)->get();

    my ( $hostname, $ips_ar ) = @$network_ar;

    $state_obj->set(
        source_node_hostname => $hostname,
        source_node_ips      => $ips_ar,
    );

    return;
}

sub _determine_dns_updates ( $input_hr, $state_obj ) {

    my $records_to_update = Cpanel::LinkedNode::Convert::Common::Mail::DNS::determine_zone_updates( $input_hr->{'username'}, $state_obj );

    $state_obj->set( records_to_update => $records_to_update );

    return;
}

sub _copy_archive ( $input_hr, $state_obj ) {

    my $home = Cpanel::Filesys::Home::get_homematch_with_most_free_space();

    my $dir = File::Temp->newdir(
        DIR => $home,
    );

    $state_obj->set(
        tempdir            => $dir,
        target_cpmove_path => "$dir/cpmove-$input_hr->{'username'}",
    );

    Cpanel::Autodie::mkdir_if_not_exists( $state_obj->get('target_cpmove_path') );

    Cpanel::LinkedNode::Convert::ArchiveDirFromNode::receive(
        node_obj         => $state_obj->get('source_node_obj'),
        archive_dir_path => $state_obj->get('target_cpmove_path'),
        remote_dir_path  => $state_obj->get('source_backup_dir'),
    );

    $state_obj->set( target_archive_deleted => 0 );

    return;
}

sub _get_local_listaccts ($input_hr) {
    return Whostmgr::Accounts::List::listaccts(
        'searchtype'   => 'user',
        'search'       => $input_hr->{'username'},
        'searchmethod' => 'exact',
    );
}

sub _local_restore ( $input_hr, $state_obj ) {

    # These technically shouldn’t even be in the cpmove file, but pass them to restorepkg anyway
    my $disabled = {};
    $disabled->{$_}{'all'} = 1 for @_DISABLED_RESTOREPKG_MODULES;

    my $indent = $input_hr->{'output_obj'}->create_indent_guard();

    my $restore_output_obj = Cpanel::Output::Restore::Translator::create( $input_hr->{'output_obj'} );

    require Whostmgr::Backup::Restore;
    my ( $status, $msg ) = Whostmgr::Backup::Restore::load_transfers_then_restorecpmove(
        'user'               => $input_hr->{'username'},
        'file'               => $state_obj->get('target_cpmove_path'),
        'output_obj'         => $restore_output_obj,
        'percentage_coderef' => sub { },
        'disabled'           => $disabled,
        'skipaccount'        => 1,
    );

    die $msg if !$status;

    return;
}

sub _retrieve_mail_parts_of_homedir ( $input_hr, $state_obj ) {
    require Cpanel::LinkedNode::Convert::FromDistributed::Mail::RetrieveHomedirMail;
    Cpanel::LinkedNode::Convert::FromDistributed::Mail::RetrieveHomedirMail::retrieve(
        node_obj => $state_obj->get('source_node_obj'),
        username => $input_hr->{'username'},
    );

    return;
}

sub _local_normalize_email ( $input_hr, $ ) {

    my $homedir = Cpanel::PwCache::gethomedir( $input_hr->{'username'} ) or do {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $input_hr->{'username'} ] );
    };

    require Cpanel::Email::Perms::User;
    Cpanel::Email::Perms::User::ensure_all_perms($homedir);

    return;
}

sub _update_dns ( $input_hr, $state_obj ) {

    my $listaccts = _get_local_listaccts($input_hr);

    my $listaccts_hr = $listaccts->[0] or do {
        die 'Local listaccts did not return user, despite that the user should exist';
    };

    my $ipv4 = $listaccts_hr->{'ip'};
    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ipv4) ) {
        die "Local listaccts returned invalid “ip” ($ipv4)";
    }

    $ipv4 = Cpanel::NAT::get_public_ip($ipv4);

    my $ipv6 = $listaccts_hr->{'ipv6'}[0];
    if ( $ipv6 && !Cpanel::Validate::IP::is_valid_ipv6($ipv6) ) {
        die "Local listaccts returned invalid “ipv6” ($ipv6)";
    }

    my $funcname = $state_obj->get('defer_dns') ? 'plan_zone_updates' : 'do_zone_updates';

    my @deferred = Cpanel::LinkedNode::Convert::FromDistributed::Mail::DNS->can($funcname)->(
        username => $input_hr->{'username'},
        ipv4     => $ipv4,
        ipv6     => $ipv6,
        records  => $state_obj->get('records_to_update'),
    );

    return \@deferred;
}

sub _unset_worker_node ( $input_hr, $state_obj ) {
    my $guard = Cpanel::Config::CpUserGuard->new( $input_hr->{'username'} );

    my $node_ar = Cpanel::LinkedNode::Worker::Storage::read( $guard->{'data'}, "Mail" );

    $state_obj->set(
        original_node_alias => $node_ar->[0],
        original_node_token => $node_ar->[1],
    );

    $guard->unset_worker_node('Mail');
    $guard->save();
    return;
}

sub _remove_from_linked_node_cache ( $input_hr, $ ) {
    my $p = Cpanel::LinkedNode::AccountCache->new_p()->then(
        sub ($cache) {
            my $needs_save = $cache->remove_cpuser( $input_hr->{'username'} );
            return $needs_save && $cache->save_p();
        },
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _restore_to_linked_node_cache ( $input_hr, $state_obj ) {
    my $p = Cpanel::LinkedNode::AccountCache->new_p()->then(
        sub ($cache) {
            $cache->set_user_parent_data(
                $input_hr->{'username'},
                'Mail',
                $state_obj->get('source_node_obj')->alias(),
            );
            return $cache->save_p();
        },
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _kick_source_connections ( $input_hr, $state_obj ) {
    my $set_p = Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::kick_source_connections_p( $input_hr, $state_obj );

    Cpanel::PromiseUtils::wait_anyevent($set_p);

    return;
}

sub _restore_worker_node ( $input_hr, $state_obj ) {
    my $guard = Cpanel::Config::CpUserGuard->new( $input_hr->{'username'} );

    $guard->set_worker_node(
        'Mail',
        $state_obj->get('original_node_alias'),
        $state_obj->get('original_node_token'),
    );

    $guard->save();

    return;
}

sub _delete_local_archive ( $input_hr, $state_obj ) {

    if ( !$state_obj->get('target_archive_deleted') ) {
        require File::Path;
        File::Path::remove_tree( $state_obj->get('target_cpmove_path') );
    }

    return;
}

sub _restore_dns ( $input_hr, $state_obj ) {
    require Cpanel::DnsUtils::Batch;

    my @name_type_value;

    for my $rec_hr ( @{ $state_obj->get('records_to_update') } ) {
        my $value;

        if ( $rec_hr->{'type'} eq 'MX' ) {
            $value = "@{$rec_hr}{'preference','exchange'}";
        }
        elsif ( $rec_hr->{'type'} eq 'CNAME' ) {
            $value = $rec_hr->{'cname'};
        }
        elsif ( grep { $_ eq $rec_hr->{'type'} } qw( A AAAA ) ) {
            $value = $rec_hr->{'address'};
        }
        else {
            die "Bad record type to restore: $rec_hr->{'type'}";
        }

        my $stripped_name = $rec_hr->{'name'} =~ s<\.\z><>r;

        push @name_type_value, [ $stripped_name, $rec_hr->{'type'}, $value ];
    }

    Cpanel::DnsUtils::Batch::set( \@name_type_value );

    return;
}

1;
