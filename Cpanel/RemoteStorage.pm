package Cpanel::RemoteStorage;

# cpanel - Cpanel/RemoteStorage.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteStorage

=head1 SYNOPSIS

    my $mount_path = Cpanel::RemoteStorage::add_nfs( $hostname_or_ip, $export_path, @opts );
    Cpanel::RemoteStorage::remove_nfs($mount_path);

    my @mounts = Cpanel::RemoteStorage::get();

=head1 DESCRIPTION

This module controls the system’s cP-controlled remote storage directories.
Such directories can store user home directories or any other system state
that it’s useful to store remotely.

As of now this can only tolerate up to 1 entry, and that entry B<<MUST> be
NFS. In the future we may want to support more, so the interface is designed
to allow it (someday).

=head1 SEE ALSO

L<Cpanel::NFS> implements useful “pre-flight” verifications.

=cut

#----------------------------------------------------------------------

use Carp         ();
use Config::Tiny ();

use Cpanel::Imports;

use Cpanel::Async::EasyLock    ();
use Cpanel::Autodie            ();
use Cpanel::Context            ();
use Cpanel::Exception          ();
use Cpanel::FileUtils::Dir     ();
use Cpanel::FileUtils::Write   ();
use Cpanel::Homedir::Search    ();
use Cpanel::LoadFile           ();
use Cpanel::PromiseUtils       ();
use Cpanel::Systemd            ();
use Cpanel::Try                ();
use Cpanel::Validate::UserNote ();

my $_DIR_BASENAME = 'remote-storage';

our $_LOCAL_CP_DIR = "/opt/cpanel";

# overridden in tests
our $_SYSTEMD_FILE_DIR = '/etc/systemd/system';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $err = get_comment_error( $COMMENT )

This method is a passthrough to Cpanel::Validate::UserNote::why_invalid
which is itself a passthrough to the cPUserNote validation in the
@cpanel/validators TypeScript library.

Returns a translated error string that explains why $COMMENT is invalid.

=cut

sub get_comment_error ($comment) {
    return Cpanel::Validate::UserNote::why_invalid($comment);
}

=head2 $local_path = add_nfs( $HOSTNAME_OR_IP, $REMOTE_PATH, \@OPTS [, $COMMENT] )

Adds an NFS mount and returns the path where it’s mounted.
For allowed @OPTS see L<nfs(5)> and L<mount(8)>. $COMMENT defaults
to an empty string and is validated with C<get_comment_error()> above.

The newly-created mount will have a C<revision> of 1. (cf. C<get()> below)

As of now, if you try to add a 2nd path, an exception is thrown.

This also synchronizes the system configuration accordingly;
i.e., after this function returns, the NFS mount is available at
the returned $local_path.

B<IMPORTANT:> This does B<NOT> verify the mount’s integrity!
It is expected that you’ll have called logic like L<Cpanel::NFS>
to ensure that the mount works as it should.

=cut

sub add_nfs ( $hostname_or_ip, $export_path, $opts_ar, $comment = q<> ) {    ## no critic qw(ManyArgs) - superfluous

    if ( my $err = get_comment_error($comment) ) {
        Carp::croak "$err\n";
    }

    my $lock = _get_lock();

    if ( _get_mount_filenames() ) {
        die "Cannot add more than one remote storage entry!\n";
    }

    my $local_path = _create_mount_path();

    my $systemd_name = Cpanel::Systemd::path_to_mount_filename($local_path);

    # We are allowing the addition of the parameter whmtimeoutsec=XX, which allows the
    # user to specify NFS mount timeout.  If we did not it would add it under Mount/Options
    # But it needs to be its own parameter TimeoutSecs=XX

    my $opts_clean = [];
    my $timeout    = 15;    # this is the default, but we will specify it regardless

    foreach my $opt ( @{$opts_ar} ) {
        if ( index( $opt, ',' ) >= 0 || scalar( $opt =~ tr/=// ) > 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', "Invalid value “[_1]” for the “[_2]” setting.", [ $opt, "option" ] );
        }
        if ( index( $opt, 'whmtimeoutsec=' ) == 0 ) {
            my ( $whm, $secs ) = split( '=', $opt, 2 );
            $timeout = $secs;
        }
        else {
            push( @{$opts_clean}, $opt );
        }
    }

    my %raw_conf = (
        Unit => {
            Description => 'cPanel remote storage',
            After       => 'network.target',
        },

        Install => {
            WantedBy => 'multi-user.target',
        },

        Mount => {
            Type        => 'nfs',
            What        => "$hostname_or_ip:$export_path",
            Where       => $local_path,
            Options     => join( ',', @$opts_clean ),
            TimeoutSecs => $timeout,
        },

        'X-cPanel' => {
            Comment  => $comment,
            Revision => 1,
        },
    );

    my $config = Config::Tiny->new();
    $config->{$_} = $raw_conf{$_} for keys %raw_conf;

    Cpanel::Try::try(
        sub {

            # write(), not overwrite(), since for now we only allow
            # one entry.
            #
            Cpanel::FileUtils::Write::write(
                "$_SYSTEMD_FILE_DIR/$systemd_name",
                $config->write_string(),
            );
        },
        'Cpanel::Exception::ErrnoBase' => sub ($err) {
            die if $err->error_name() ne 'EEXIST';

            die 'Multiple mounts are not allowed!';
        },
    );

    Cpanel::Systemd::systemctl('daemon-reload');
    Cpanel::Systemd::systemctl( 'restart', $systemd_name );
    Cpanel::Systemd::systemctl( 'enable',  $systemd_name );

    return $local_path;
}

=head2 $revision = update_nfs( $LOCAL_PATH, $REVISION, %NEW_VALUES )

Updates an NFS mount previously created via C<add_nfs()> above.

The given $REVISION should be the mount’s C<revision> value as C<get()>
(below) returns. (The value is 1 for all newly-created mounts.)

Returns the entry’s new C<revision>.

%NEW_VALUES are:

=over

=item * C<host>

=item * C<remote_path>

=item * C<options> (array reference)

=item * C<comment> (optional)

=back

B<IMPORTANT:> As with C<add_nfs()>, this does B<NOT> verify anything about
the NFS mount.

=cut

sub update_nfs ( $local_path, $revision, %changes ) {
    if ( my $err = get_comment_error( $changes{'comment'} ) ) {
        Carp::croak "$err\n";
    }

    my $systemd_name = Cpanel::Systemd::path_to_mount_filename($local_path);

    my $systemd_path = "$_SYSTEMD_FILE_DIR/$systemd_name";

    my $lock = _get_lock();

    my $cnf_str = Cpanel::LoadFile::load_if_exists($systemd_path) // do {
        Carp::croak( Cpanel::Exception->create( 'This system does not mount remote storage at “[_1]”.', [$local_path] ) );
    };
    my $cnf = Config::Tiny->read_string($cnf_str);

    if ( $cnf->{'X-cPanel'}{'Revision'} ne $revision ) {
        die Cpanel::Exception::create_raw( 'Stale', "Wrong revision: $revision" );
    }

    my $host        = $changes{'host'};
    my $remote_path = $changes{'remote_path'};
    my $opts_ar     = $changes{'options'};
    my $comment     = $changes{'comment'} // q<>;

    $cnf->{'Mount'}{'What'}       = "$host:$remote_path";
    $cnf->{'Mount'}{'Options'}    = join( ',', @$opts_ar );
    $cnf->{'X-cPanel'}{'Comment'} = $comment;
    $cnf->{'X-cPanel'}{'Revision'}++;

    Cpanel::FileUtils::Write::overwrite(
        $systemd_path,
        $cnf->write_string(),
    );

    Cpanel::Systemd::systemctl('daemon-reload');
    Cpanel::Systemd::systemctl( 'restart', $systemd_name );

    return $cnf->{'X-cPanel'}{'Revision'};
}

sub _create_mount_path {

    # Randomize the mount path so that a subsequent entry won’t have
    # to be “ordered”.
    #
    return "$_LOCAL_CP_DIR/$_DIR_BASENAME-" . sprintf( '%x', substr( rand, 2, 5 ) );
}

=head2 $yn = remove( $LOCAL_PATH )

Cancels the indicated NFS mount entirely, synchronizing system state
accordingly.

Returns a boolean that indicates whether $MOUNT_PATH referred to an
actual mount.

=cut

sub remove ($local_path) {
    if ( Cpanel::Homedir::Search::is_used($local_path) ) {
        die Cpanel::Exception->create( "“[_1]” contains at least 1 user’s home directory. Delete all such accounts, then retry.", [$local_path] );
    }

    local $!;

    my $systemd_name = Cpanel::Systemd::path_to_mount_filename($local_path);

    my $unlinked = Cpanel::Autodie::unlink_if_exists("$_SYSTEMD_FILE_DIR/$systemd_name");

    if ($unlinked) {
        Cpanel::Systemd::systemctl( 'disable', $systemd_name );
        Cpanel::Systemd::systemctl( 'stop',    $systemd_name );
        Cpanel::Systemd::systemctl('daemon-reload');

    }

    rmdir($local_path) or do {
        warn "rmdir($local_path): $!" if !$!{'ENOENT'};
    };

    return $unlinked;
}

=head2 @mounts = get()

Returns a list of hashrefs, one for each remote-storage mount.

Each hashref is:

=over

=item * C<type> (currently always C<nfs>)

=item * C<host>

=item * C<local_path>

=item * C<remote_path>

=item * C<options> (arrayref of strings)

=item * C<comment>

=item * C<revision>

=back

Must be called in list context.

=cut

sub get () {
    Cpanel::Context::must_be_list();

    my @mounts = _get_mount_filenames();

    my @ret;

    for my $filename (@mounts) {
        my $cnf_str = Cpanel::LoadFile::load_if_exists("$_SYSTEMD_FILE_DIR/$filename");

        next if !defined $cnf_str;

        my $cnf = Config::Tiny->read_string($cnf_str);

        my ( $opts, $what, $where ) = @{ $cnf->{'Mount'} }{ 'Options', 'What', 'Where' };

        my ( $host, $export_path ) = $what =~ m<(.+?):(.+)>;
        my @params = split m<,>, $opts;

        push @ret, {
            type        => 'nfs',
            host        => $host,
            remote_path => $export_path,
            local_path  => $where,
            options     => \@params,
            comment     => $cnf->{'X-cPanel'}{'Comment'},
            revision    => $cnf->{'X-cPanel'}{'Revision'},
        };
    }

    return @ret;
}

sub _get_mount_filenames {
    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes($_SYSTEMD_FILE_DIR);

    my $systemd_filename_base = Cpanel::Systemd::escape($_DIR_BASENAME);

    return grep { m<cpanel.+\Q$systemd_filename_base\E.+mount\z> } @$nodes_ar;
}

sub _get_lock () {
    return Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::Async::EasyLock::lock_exclusive_p(__PACKAGE__),
    );
}

1;
