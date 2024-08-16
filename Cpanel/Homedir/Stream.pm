package Cpanel::Homedir::Stream;

# cpanel - Cpanel/Homedir/Stream.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Homedir::Stream - Stream a user’s home directory

=head1 SYNOPSIS

    Cpanel::Homedir::Stream::rsync_from_cpanel(
        host => 'remote-host.com',
        destination => '/home/bob',
        api_token => 'YNSDGFHSGGNFMSDGGSMFYBSDMDFDSH',
        api_token_username => 'bob',

        setuids => ['bob'],
    );

=head1 DESCRIPTION

This module exposes logic to stream a home directory between hosts.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie          ();
use Cpanel::TempFH           ();
use Cpanel::FHUtils::FDFlags ();
use Cpanel::Rsync            ();

our $_RSYNC_USER_HOMEDIR_PATH = '/usr/local/cpanel/bin/rsync-user-homedir';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 rsync_from_cpanel( %ARGS )

Backs up a remote user’s home directory via remote cPanel to a local
directory.

%ARGS are:

=over

=item * C<host> - The peer’s name or IP address.

=item * C<destination> - The local directory where the home directory
contents will be restored. (Probably the user’s home directory.)

=item * C<api_token> - The API token to use to authenticate on the peer.

=item * C<api_token_username> - The username to give with the API
token.

=item * C<exclude> - Optional. Reference to array of paths to give to
L<rsync(1)> as exclusions. (i.e., C<--exclude=>)

=item * C<extraneous> - Optional. Either C<ignore> (default) or C<delete>.

=item * C<tls_verification> - Optional. Either C<on> (default) or C<off>.

=item * C<setuids> - Optional. Array reference of arguments to give
to L<Cpanel::AccessIds::SetUids>’s C<setuids()> function immediately
before starting L<rsync(1)>. (For example, the user’s name if you don’t
trust the peer and want to write to the local filesystem as the user.)

=back

Output from the underlying L<rsync(1)> process (STDOUT and STDERR) go
to an underlying L<Cpanel::Parser::Rsync> instance; see that module for
details of how output is handled.

Returns nothing; throws an appropriate exception on failure.

=cut

sub rsync_from_cpanel (%args) {
    _validate_rsync_opts( \%args );

    my @extra_rsync_args  = _process_optional_rsync_opts( \%args );
    my @extra_script_args = _process_optional_script_opts( \%args );

    my @extra_cprsync_args = _process_optional_cprsync_opts( \%args );

    my $tempfh = _prepare_apitoken_fh( $args{'api_token'} );
    my $fd     = fileno $tempfh;

    my $rsh = join(
        q< >,
        $_RSYNC_USER_HOMEDIR_PATH,
        @extra_script_args,
        '--cpanel',
        "--apitoken-fd=$fd",
        $args{'host'},
    );

    Cpanel::Rsync->run(
        @extra_cprsync_args,

        args => [
            @extra_rsync_args,

            '--rsh' => $rsh,

            "$args{'api_token_username'}:",
            $args{'destination'},
        ],
    );

    return;
}

sub _prepare_apitoken_fh ($content) {
    my $tempfh = Cpanel::TempFH::create();
    Cpanel::Autodie::syswrite_sigguard( $tempfh, $content );
    Cpanel::Autodie::sysseek( $tempfh, 0, 0 );

    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($tempfh);

    return $tempfh;
}

sub _process_optional_cprsync_opts ($opts_hr) {
    my @extra_saferun_args;

    if ( $opts_hr->{'setuids'} ) {
        push @extra_saferun_args, ( setuid => $opts_hr->{'setuids'} );
    }

    return @extra_saferun_args;
}

sub _process_optional_rsync_opts ($opts_hr) {
    my @args;

    my @invalid;

    if ( my $extra = $opts_hr->{'extraneous'} ) {
        if ( $extra eq 'delete' ) {
            push @args, '--delete-during';
        }
        elsif ( $extra ne 'ignore' ) {
            push @invalid, "extraneous=$extra";
        }
    }

    if ( my $exclusions = $opts_hr->{'exclude'} ) {
        push @args, "--exclude=$_" for @$exclusions;
    }

    die "invalid: @invalid" if @invalid;

    return @args;
}

sub _process_optional_script_opts ($opts_hr) {
    my @args;

    my @invalid;

    if ( my $val = $opts_hr->{'tls_verification'} ) {
        if ( $val eq 'off' ) {
            push @args, '--insecure';
        }
        elsif ( $val ne 'on' ) {
            push @invalid, "tls_verification=$val";
        }
    }

    die "invalid: @invalid" if @invalid;

    return @args;
}

sub _validate_rsync_opts ($opts_hr) {
    my @missing = sort grep { !$opts_hr->{$_} } (
        'api_token',
        'api_token_username',
        'host',
        'destination',
    );
    die "missing: @missing" if @missing;

    return;
}

1;
