package Whostmgr::XferClient;

# cpanel - Whostmgr/XferClient.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PwCache::Group            ();
use Cpanel::AdminBin::Serializer      ();
use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::Exception                 ();
use Cpanel::SafeRun::Object           ();
use Cpanel::LoadModule                ();
use Cpanel::Parser::XferStream        ();
use Cpanel::Parser::XferDownload      ();
use Cpanel::Rsync                     ();
use Cpanel::PwCache                   ();

our $MAX_READ_WAIT_TIMEOUT = ( 60 * 30 );                                     # 30 minutes
our $TIMEOUT               = ( 60 * 60 * 24 * 3 );                            # 3 Days
our $PIPE_BUF              = 4096;                                            #/usr/include/linux/limits.h:#define PIPE_BUF        4096  /* # bytes in atomic write to a pipe */
our $client_binary         = '/usr/local/cpanel/bin/whm_xfer_download-ssl';

#----------------------------------------------------------------------

#This tells which streaming methods the remote "host" supports.
#
#named parameters:
#   use_ssl (required)
#   host    (required)
#   user    (required) - i.e., the user to use to authenticate
#
#   pass OR accesshash (required)
#
#Returns a hash: {
#   streaming   => 0/1,
#   rsync       => 0/1,
#}
#
sub stream_test {
    my (%OPTS) = @_;

    _require_opts( \%OPTS, qw( use_ssl host user ) );

    _require_accesshash_or_pass( \%OPTS );

    $OPTS{'xferstreamtest'} = 1;

    my $saferun = Cpanel::SafeRun::Object->new(
        'program' => $client_binary,
        'stdin'   => Cpanel::AdminBin::Serializer::Dump( \%OPTS ),
    );

    if ( $saferun->CHILD_ERROR() ) {
        die Cpanel::Exception->create_raw( "Streaming transfer test failed: " . $saferun->stderr() . ': ' . $saferun->autopsy() );
    }

    my $stdout = $saferun->stdout();
    if ( !$stdout ) {
        die Cpanel::Exception->create_raw( "Streaming transfer test failed: no content from remote server: " . $saferun->stderr() );
    }

    my %support = (
        'streaming' => ( $stdout =~ m{streaming supported}i ? 1 : 0 ),
        'rsync'     => ( $stdout =~ m{rsync supported}i     ? 1 : 0 ),
        'dsync'     => ( $stdout =~ m{dsync supported}i     ? 1 : 0 ),
    );

    return \%support;
}

#This downloads a file from the remote server.
#
#named parameters:
#   use_ssl             (required)
#   host                (required)
#   user                (required)
#   source_file_path    (required)
#   target_file_path    (required)
#
#   pass OR accesshash (required)
#
#Two-part return.
#
sub download {
    my (%OPTS) = @_;

    _require_opts(
        \%OPTS,
        qw(
          use_ssl
          host
          user
          source_file_path
          target_file_path
        )
    );

    _require_accesshash_or_pass( \%OPTS );

    $OPTS{'dest'} = delete $OPTS{'target_file_path'};
    $OPTS{'file'} = delete $OPTS{'source_file_path'};

    my $xferdownload_parser = Cpanel::Parser::XferDownload->new();

    my $saferun = Cpanel::SafeRun::Object->new(
        'program'      => $client_binary,
        'stdin'        => Cpanel::AdminBin::Serializer::Dump( \%OPTS ),
        'read_timeout' => $MAX_READ_WAIT_TIMEOUT,
        'timeout'      => $TIMEOUT,
        stdout         => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $xferdownload_parser->process_data(@_);
            }
        ),
    );

    return ( 0, "Download failed: " . $saferun->stderr() . ': ' . $saferun->autopsy() ) if $saferun->CHILD_ERROR();

    return $xferdownload_parser->finish() ? ( 1, 'OK' ) : ( 0, 'Unknown error' );
}

#This takes two configuration hashrefs.
#
#FIRST HASH: Same inputs as stream_test
#
#SECOND HASH:
#   user        (required) - the remote user whose homedir to stream
#   target_dir  (required) - the path into which to untar
#   excludes    (optional) - tar PATTERNs to exclude from the archive
#   uid AND gid (optional) - If given, server will setuid before archiving.
#
#Returns the success status (boolean) from a Cpanel::Parser::XferStream object.
#
sub stream {
    my ( $hr_AUTHOPTS, $hr_OPTS ) = @_;

    my $request = _streaming_args_parser( $hr_AUTHOPTS, $hr_OPTS );
    $request->{'xferstream'} = 1;

    my $xferstream_parser = Cpanel::Parser::XferStream->new();

    my $saferun = Cpanel::SafeRun::Object->new(
        'program'      => $client_binary,
        'read_timeout' => $MAX_READ_WAIT_TIMEOUT,
        'timeout'      => $TIMEOUT,
        'stdin'        => Cpanel::AdminBin::Serializer::Dump($request),
        'stdout'       => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $xferstream_parser->process_data(@_);
            }
        ),
    );

    die Cpanel::Exception->create_raw( "Streaming failed: " . $saferun->stderr() . ': ' . $saferun->autopsy() ) if $saferun->CHILD_ERROR();

    return $xferstream_parser->finish();
}

#Same arguments as stream().
#
#Returns the success status (boolean) from a Cpanel::Parser::Rsync object.
#
sub rsync {
    my ( $hr_AUTHOPTS, $hr_OPTS ) = @_;

    my $request = _streaming_args_parser( $hr_AUTHOPTS, $hr_OPTS );

    my $setuid = delete $request->{'setuid'};
    my $delete = delete $request->{'delete'};

    my $direction = ( $request->{'direction'} ||= 'download' );

    $request->{'xferrsync'} = 1 if !$request->{'syncstream'};

    my @excludes = $hr_OPTS->{'excludes'} ? @{ $hr_OPTS->{'excludes'} } : ();
    my @exclude_args;
    if (   $hr_OPTS->{'excludes'}
        && ref $hr_OPTS->{'excludes'} eq 'ARRAY'
        && scalar @{ $hr_OPTS->{'excludes'} } ) {
        @exclude_args = map { "--exclude=$_" } @{ $hr_OPTS->{'excludes'} };
    }

    my $serialized_request = Cpanel::AdminBin::Serializer::Dump($request);

    # In practice this should be about 1200 bytes.
    # This doesn't even get us close to the 4096 byte limit.
    if ( length $serialized_request > $PIPE_BUF ) {
        die Cpanel::Exception->create_raw("The request may not exceed $PIPE_BUF bytes in order to be passed over a pipe to “$client_binary”.");
    }

    local $!;

    my ( $read_fh, $write_fh );
    {

        #Make sure that these filehandles will stay open once the forked
        #process exec()s so that $client_binary can read $serialized_request.
        local $^F = 1000;
        pipe( $read_fh, $write_fh ) or die "pipe() failed: $!";
    }

    syswrite( $write_fh, $serialized_request ) or die Cpanel::Exception::create( 'IO::WriteError', [ error => $! ] );
    close $write_fh;

    my $rsh_command = "$client_binary --read_input_from_fd=" . fileno($read_fh);

    return Cpanel::Rsync->run(
        'setuid' => $setuid,
        'args'   => [
            '--force',
            '--rsh' => $rsh_command,
            ( map { ( '--exclude' => $_ ) } @excludes ),
            ( $delete                           ? '--delete-during' : () ),
            ( $hr_OPTS->{'preserve_hard_links'} ? '--hard-links'    : () ),
            (
                $direction eq 'upload'
                ? ( "$hr_OPTS->{'source_dir'}/" => 'remote:' )
                : ( 'remote:' => "$hr_OPTS->{'target_dir'}/" )
            ),
        ]
    );
}

#Same arguments as stream().
#
#Returns the success status (boolean) from a Cpanel::Parser::Dsync object.
#

#Example Inputs
#$hr_AUTHOPTS = {
#  'user' => 'root',
#  'pass' => '0',
#  'host' => 'ip',
#  'use_ssl' => '1',
#  'sourceuser' => 'user',
#  'accesshash' => '',
#  'version' => 1
#};
#$hr_OPTS = {
#  'user' => 'aimme',
#};
sub dsync {
    my ( $hr_AUTHOPTS, $hr_OPTS ) = @_;

    $hr_OPTS->{'target_dir'} = '/tmp';
    $hr_OPTS->{'uid'}        = 0;
    $hr_OPTS->{'gid'}        = 0;
    my $request = _streaming_args_parser( $hr_AUTHOPTS, $hr_OPTS );

    $request->{'xferdsync'} = 1;

    my $serialized_request = Cpanel::AdminBin::Serializer::Dump($request);

    # In practice this should be about 1200 bytes.
    # This doesn't even get us close to the 4096 byte limit.
    if ( length $serialized_request > $PIPE_BUF ) {
        die Cpanel::Exception->create_raw("The request may not exceed $PIPE_BUF bytes in order to be passed over a pipe to “$client_binary”.");
    }

    local $!;

    my ( $read_fh, $write_fh );
    {

        #Make sure that these filehandles will stay open once the forked
        #process exec()s so that $client_binary can read $serialized_request.
        local $^F = 1000;
        pipe( $read_fh, $write_fh ) or die "pipe() failed: $!";
    }

    syswrite( $write_fh, $serialized_request ) or die Cpanel::Exception::create( 'IO::WriteError', [ error => $! ] );
    close $write_fh;

    Cpanel::LoadModule::load_perl_module('Cpanel::Dovecot::Sync');

    my $target_user = $hr_OPTS->{'target_user'} or die "“target_user” must be passed in hr_OPTS";

    my $operation = $hr_OPTS->{'operation'} or die "“operation” must be “mirror”, “mirror-reversed”, “backup”, “restore”, “mirror-one-way”, “mirror-reversed-one-way”, “backup-one-way”, or “restore-one-way”";
    my @args;
    if ( $operation =~ m{^mirror-reversed} ) {
        push @args, 'sync';
        push @args, '-R';
    }
    elsif ( $operation =~ m{^mirror} ) {
        push @args, 'sync';
    }
    elsif ( $operation =~ m{^backup} ) {
        push @args, 'backup';
    }
    elsif ( $operation =~ m{^restore} ) {
        push @args, 'backup';
        push @args, '-R';
    }
    else {
        die "Unknown operation: “$operation”";
    }

    push @args, (
        '-u', $target_user,
        @Cpanel::Dovecot::Sync::DEFAULT_EXCLUDES,
    );

    # One way operations are generally not recommened
    # Its better to make a copy of the source if you
    # do not want to modify it and sync from there
    # with mirror.
    if ( $operation =~ m{-one-way$} ) {
        push @args, '-1', '-f';
    }

    push @args, $client_binary, "--read_input_from_fd=" . fileno($read_fh);

    require Cpanel::Dsync;
    return Cpanel::Dsync->run( 'args' => \@args );
}

sub _streaming_args_parser {
    my ( $hr_AUTHOPTS, $hr_OPTS ) = @_;

    my @missing = grep { !defined $hr_AUTHOPTS->{$_} } qw( use_ssl host user );

    if (@missing) {
        die "Missing the following required parameter(s) from the first hashref: @missing";
    }

    if ( !$hr_AUTHOPTS->{'accesshash'} && !$hr_AUTHOPTS->{'pass'} ) {
        die "Specify either “accesshash” or “pass” in the first hashref.";
    }

    @missing = grep { !defined $hr_OPTS->{$_} } qw(user target_dir);

    if (@missing) {
        die "Missing the following required parameter(s) from the second hashref: @missing";
    }

    my %request = (
        %{$hr_AUTHOPTS},
        xferuser => $hr_OPTS->{'user'},
        xferdest => $hr_OPTS->{'target_dir'},
        ( $hr_OPTS->{'source_dir'} ? ( 'xfersource' => $hr_OPTS->{'source_dir'} ) : () ),
        ( $hr_OPTS->{'delete'}     ? ( 'delete'     => $hr_OPTS->{'delete'} )     : () ),
    );

    $request{'excludes'} = $hr_OPTS->{'excludes'} if ref( $hr_OPTS->{'excludes'} ) eq 'ARRAY';

    if ( $> == 0 ) {
        if ( defined $hr_OPTS->{'uid'} && defined $hr_OPTS->{'gid'} ) {
            $request{'setuid'} = [ $hr_OPTS->{'uid'}, $hr_OPTS->{'gid'}, $hr_OPTS->{'supplemental_gids'} ? @{ $hr_OPTS->{'supplemental_gids'} } : () ];
        }
        else {
            my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user( $hr_OPTS->{'user'} );
            $request{'setuid'} = [ ( Cpanel::PwCache::getpwnam( $hr_OPTS->{'user'} ) )[ 2, 3 ], @supplemental_gids ];
        }
    }
    return \%request;
}

sub _require_opts {
    my ( $opts_hr, @opts ) = @_;

    my @missing = grep { !defined $opts_hr->{$_} } @opts;

    if (@missing) {
        die "Missing the following required parameter(s): @missing";
    }

    return 1;
}

sub _require_accesshash_or_pass {
    my ($opts_hr) = @_;

    if ( !$opts_hr->{'accesshash'} && !$opts_hr->{'pass'} ) {
        die "Specify either “accesshash” or “pass”.";
    }
}

1;
