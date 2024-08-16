# cpanel - Whostmgr/Transfers/LocalRestore.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Transfers::LocalRestore;

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::LocalRestore - Encapsulates the logic required to restore local cpmove data

=head1 SYNOPSIS

    use Whostmgr::Transfers::LocalRestore;

    my $opts_hr = {
        initiator    => "whoever did the thing",
        cpmovepath   => "/path/to/cpmove-username.tar.gz",
        overwrite    => 1,
        dedicated_ip => 1,
        restricted   => 0,
        update_a_rec => "all",
    };

    my $transfer_session_id = Whostmgr::Transfers::LocalRestore::start_local_cpmove_restore( $opts_hr );

=head1 DESCRIPTION

This module provide functions to encapsulate the process of creating a transfer session, enqueuing
an AccountLocal transfer item to restore local cpmove data, and starting the transfer session.

=head1 FUNCTIONS

=cut

use Try::Tiny;

use Cpanel::Exception ();

use Cpanel::Autodie qw(exists);

use Whostmgr::Transfers::Utils::LinkedNodes ();

my @_REQUIRED_OPTIONS = qw(
  cpmovepath
  initiator
);

my @_BOOLEAN_OPTIONS = qw(
  dedicated_ip
  overwrite
  restricted
  delete_archive
);

=head2 $transfer_session_id = start_local_cpmove_restore( $opts_hr )

Creates and starts an AccountLocal restore

=over

=item Input

=over

This function accepts a single HASHREF argument specifying the options for the restore with
the following allowed hash keys:

=over

=item initiator (required)

A string identifying who or what is initiating the restore.

=item cpmovepath (required)

A path on the local filesystem to either a cpmove tarball or a directory containing the
extracted data from a cpmove tarball.

=item username (optional)

The username to give to the newly-created account. If not given, a username
will be derived from C<cpmovepath>.

=item dedicated_ip (optional)

Either 0 or 1 to indicate whether or not to assign the restore account a dedicated IP.

This option defaults to 0.

=item overwrite (optional)

Either 0 or 1 to indicate whether or not to overwrite any existing account data during
the restore.

This option defaults to 0.

=item restricted (optional)

Either 0 or 1 to indicate whether or not to executed the transfer in restricted mode.

This option defaults to 0.

=item update_a_rec (optional)

Either “all” or ”basic” to indicate whether all of the accounts A records should be updated
during the restore or only the basic cPanel related A records.

This option defaults to “all”.

=item delete_archive (optional)

Either 0 or 1 to indicate whether or not to remove the cpmove data after the transfer completes.

This option defaults to 0.

=back

=back

=item Output

=over

On success this function returns the id of the transfer session that was created and started.

This function dies on failure.

=back

=back

=cut

sub start_local_cpmove_restore ($opts_hr) {

    _validate_options($opts_hr);
    _do_preflight();

    my @passthrough_args = (
        'initiator',
        'cpmovepath',
        'username',
        values %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER,
    );

    my $real_opts_hr = {
        overwrite      => $opts_hr->{overwrite}        || 0,
        dedicated_ip   => $opts_hr->{dedicated_ip}     || 0,
        restricted     => $opts_hr->{restricted}       || 0,
        update_a_rec   => $opts_hr->{update_a_records} || "all",
        delete_archive => $opts_hr->{delete_archive}   || 0,

        %{$opts_hr}{@passthrough_args},
    };

    $real_opts_hr->{username} //= _get_username_from_path($real_opts_hr);

    my $transfer_session_id = _create_transfer_session($real_opts_hr);
    _start_transfer_session( $transfer_session_id, $real_opts_hr->{overwrite} );

    return $transfer_session_id;
}

sub _validate_options ($opts_hr) {

    _validate_cpmove_path($opts_hr);
    _validate_boolean_options($opts_hr);
    _validate_update_a_records($opts_hr);

    return;
}

sub _do_preflight {

    require Whostmgr::Transfers::Session::Preflight::Restore;
    my ( $adjust_ok, $adjust_msg ) = Whostmgr::Transfers::Session::Preflight::Restore::ensure_mysql_is_sane_for_restore();
    die $adjust_msg if !$adjust_ok;

    return;
}

sub _validate_required_options ($opts_hr) {

    my @missing = grep { !length $opts_hr->{$_} } @_REQUIRED_OPTIONS;
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] ) if @missing;

    return;
}

sub _validate_cpmove_path ($opts_hr) {

    if ( !Cpanel::Autodie::exists( $opts_hr->{cpmovepath} ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The path “[_1]” does not exist.", [ $opts_hr->{cpmovepath} ] );
    }

    return;
}

sub _validate_boolean_options ($opts_hr) {

    my @invalid_booleans;
    foreach my $param (@_BOOLEAN_OPTIONS) {
        if ( exists $opts_hr->{$param} && ( !length $opts_hr->{$param} || ( $opts_hr->{$param} ne "0" && $opts_hr->{$param} ne "1" ) ) ) {
            push @invalid_booleans, $param;
        }
    }

    if (@invalid_booleans) {
        die Cpanel::Exception::create( 'InvalidParameters', "The [list_and_quoted,_1] [numerate,_2,parameter,parameters] must be [list_or_quoted,_3].", [ \@invalid_booleans, scalar @invalid_booleans, [ 0, 1 ] ] );
    }

    return;
}

sub _validate_update_a_records ($opts_hr) {

    return if !exists $opts_hr->{update_a_records};

    if ( !length $opts_hr->{update_a_records} || ( $opts_hr->{update_a_records} ne "all" && $opts_hr->{update_a_records} ne "basic" ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The [list_and_quoted,_1] [numerate,_2,parameter,parameters] must be [list_or_quoted,_3].", [ ["update_a_records"], 1, [ "all", "basic" ] ] );
    }

    return;
}

sub _get_username_from_path ($opts_hr) {

    require Whostmgr::Transfers::Locations;
    my $username = Whostmgr::Transfers::Locations::match_quickrestore_path( $opts_hr->{cpmovepath} ) or die "Failed to deduce username from path “$opts_hr->{cpmovepath}”!";

    require Cpanel::AcctUtils::Account;
    if ( !$opts_hr->{overwrite} && Cpanel::AcctUtils::Account::accountexists($username) ) {
        die Cpanel::Exception->create( "The system cannot restore the account “[_1]” because an account with that name already exists on this system.", [$username] );
    }

    return $username;
}

sub _create_transfer_session ($opts_hr) {

    require Whostmgr::Transfers::Session::Constants;
    require Whostmgr::Transfers::Session::Setup;
    require Cpanel::Hostname;
    my ( $ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj(
        {
            'initiator'           => $opts_hr->{initiator},
            'create'              => 1,
            'session_id_template' => scalar Cpanel::Hostname::gethostname(),
        },
        {
            'session' => {
                'scriptdir' => '/scripts',

                #This appears to be unused. Leaving it in as copied from whostmgr5.pl.
                'state' => 'preflight',

                'session_type' => $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'Local'},
            },
            'queue'   => { 'RESTORE' => 0 },
            'options' => {
                'unrestricted' => $opts_hr->{restricted} ? 0 : 1,
            }
        }
    );

    die $session_obj if !$ok;

    my $transfer_session_id = $session_obj->id();

    $session_obj->set_source_host('localhost');

    my @passthrough_args = (
        values %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER,
    );

    my %enqueue_args = (
        'user'                        => $opts_hr->{username},
        'localuser'                   => $opts_hr->{username},
        'cpmovefile'                  => $opts_hr->{cpmovepath},
        'replaceip'                   => $opts_hr->{update_a_rec},
        'ip'                          => $opts_hr->{dedicated_ip} ? 1 : 0,
        'skipaccount'                 => ( ( $opts_hr->{overwrite} && Cpanel::AcctUtils::Account::accountexists( $opts_hr->{username} ) ) ? 1 : 0 ),
        'overwrite_sameowner_dbusers' => $opts_hr->{overwrite},
        'overwrite_sameowner_dbs'     => $opts_hr->{overwrite},

        %{$opts_hr}{@passthrough_args},
    );

    $session_obj->enqueue(
        ( $opts_hr->{delete_archive} ? 'AccountUpload' : 'AccountLocal' ),
        \%enqueue_args,
        $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'RESTORE_PENDING'}
    );

    $session_obj->disconnect();

    return $transfer_session_id;
}

sub _start_transfer_session ( $transfer_session_id, $overwrite ) {

    require Whostmgr::Transfers::Session::Start;
    my $err;
    try {
        my $opts_ref = {};
        $opts_ref->{'ignore_disk_space'} = 1 if $overwrite;
        my ( $status, $msg ) = Whostmgr::Transfers::Session::Start::start_transfer_session( $transfer_session_id, $opts_ref );
        die $msg if !$status;
    }
    catch {
        $err = $_;
    };

    die Cpanel::Exception::get_string($err) if $err;

    return;
}

1;
