package Cpanel::SSL::Auto::Log;

# cpanel - Cpanel/SSL/Auto/Log.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Log - logging logic for AutoSSL

=head1 SYNOPSIS

    #Each item is a hashref with “provider” and “start_time”.
    my @catalog = Cpanel::SSL::Auto::Log->get_catalog();
    my @deleted = Cpanel::SSL::Auto::Log->purge_old_logs();

    #Each item is a hashref of the sort that Cpanel::Output::TimeStamp creates.
    my $entries_ar = Cpanel::SSL::Auto::Log->read( $start_time_isoz );

    #Start a new log file for right now. (die() if there’s already one.)
    my $log = Cpanel::SSL::Auto::Log->new(
        provider => $provider,
        username => $username,  #optional; defaults to “*”, meaning all users
    );

    #Open an existing log file. (die() if there isn’t one.)
    my $log = Cpanel::SSL::Auto::Log->new(
        start_time => $start_time,
    );

    $log->get_start_time();

    $log->info($msg);
    $log->success($msg);
    $log->warn($msg);
    $log->increase_indent_level();
    $log->error($msg);
    $log->decrease_indent_level();

    $log->set_completed();

=head1 NOTES

Note that C<start_time> is always: YYYY-MM-DDTHH-MM-SSZ. This subset of ISO
8601 may be expanded upon later, but for now this is the only format.

=cut

use cPstrict;

use Try::Tiny;

use Cpanel::Autodie                     ();
use Cpanel::Context                     ();
use Cpanel::Exception                   ();
use Cpanel::Fcntl                       ();
use Cpanel::FileUtils::Read             ();
use Cpanel::JSON                        ();
use Cpanel::LoadFile::ReadFast          ();
use Cpanel::Mkdir                       ();
use Cpanel::Output::TimeStamp           ();
use Cpanel::Output::Formatted::Terminal ();
use Cpanel::Output::Multi               ();
use Cpanel::Regex                       ();    ## PPI NO PARSE - mis-parse
use Cpanel::SSL::Auto::Constants        ();
use Cpanel::SSL::Auto::Utils            ();
use Cpanel::UPID                        ();
use Cpanel::Time::ISO                   ();
use Cpanel::Validate::Time              ();

my $MAX_ATTEMPTS_TO_CREATE_UNIQUE_LOG_NAME = 500;    # Max number of seconds to time warp into the future to find a unique log name

my $log_entry_dirname_regexp = qq<($Cpanel::Regex::regex{iso_z_time})>;

sub _DIR { return '/var/cpanel/logs/autossl' }

#----------------------------------------------------------------------
# Class methods

=head2 $entries_ar = I<CLASS>->read( START_TIME_ISOZ )

Reads an AutoSSL log and returns the entries as an array reference.

Each entry is a hash reference.

When successfully read:

=over

=item C<pid> - the AutoSSL process ID

=item C<timestamp> - ISO/Z format

=item C<user> - the username

=item C<indent> - unsigned int, the log indent level. Useful for display.

=item C<type> - one of: C<out>, C<warn>, C<error>, C<success>

=item C<contents> - string, the content

=back

When unsuccessfully read:

=over

=item C<raw> - the raw text of the log. These are the bytes that the system
failed to parse.

=item C<parse_error> - string, the reason why the parse failed

=back

=cut

sub read {
    my ( $class, $start_time ) = @_;

    Cpanel::Validate::Time::iso_or_die($start_time);

    my $path = $class->_DIR() . "/$start_time/json";

    #We can end up reading a partially-written file here,
    #but that’s ok since we accommodate invalid JSON below.
    Cpanel::Autodie::open( my $rfh, '<', $path );

    local ( $!, $^E );

    # We are going to store this all in memory so we might as well
    # use read_all_fast
    my $data = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $rfh, $data );

    #TODO: Find/make a separate parser for this format.
    #----------------------------------------------------------------------
    my @entries;
    local $@;    #for speed
    @entries = map {
        eval { Cpanel::JSON::Load($_) }
          // { raw => $_, parse_error => Cpanel::Exception::get_string_no_id($@) }
    } split( m{\n}, $data );
    if ($!) {
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $path, error => $! ] );
    }

    #----------------------------------------------------------------------

    Cpanel::Autodie::close($rfh);

    return \@entries;
}

sub get_catalog {
    my ($class) = @_;

    Cpanel::Context::must_be_list();

    my @catalog;

    my $dir = $class->_DIR();

    Cpanel::Autodie::exists($dir);
    if ( -d _ ) {
        Cpanel::FileUtils::Read::for_each_directory_node(
            $dir,
            sub {
                return if !m<\A$log_entry_dirname_regexp\z>xo;

                my $node = $_;

                try {
                    my $provider = Cpanel::Autodie::readlink("$dir/$_/provider");
                    my $username = Cpanel::Autodie::readlink("$dir/$_/username");

                    # The original process’s UPID.
                    my $orig_upid = Cpanel::Autodie::readlink_if_exists("$dir/$_/upid");

                    my %entry = (
                        start_time => $1,
                        provider   => $provider,
                        username   => $username,
                        upid       => $orig_upid,
                    );

                    $class->_augment_log_entry_with_process_data( \%entry );

                    push @catalog, \%entry;
                }
                catch {
                    warn "Failed to process “$node”: $_";
                };
            },
        );
    }

    return @catalog;
}

sub _augment_log_entry_with_process_data {
    my ( $class, $entry_hr ) = @_;

    my $process_is_active;

    # The “upid” is recorded from v76 onward. As long as there are
    # potential AutoSSL logs around from before then, we have to accommodate
    # the case of a missing “upid”.
    if ( $entry_hr->{'upid'} ) {
        my $orig_pid = Cpanel::UPID::extract_pid( $entry_hr->{'upid'} );
        my $cur_upid = Cpanel::UPID::get($orig_pid) // q<>;

        $process_is_active = ( ( $cur_upid // q<> ) eq $entry_hr->{'upid'} ) ? 1 : 0;
    }

    my $dir         = $class->_DIR();
    my $in_progress = $process_is_active || Cpanel::Autodie::exists_nofollow("$dir/$entry_hr->{'start_time'}/in_progress");

    # NB: “original_process_is_complete” is currently unused.
    @{$entry_hr}{ 'in_progress', 'original_process_is_complete' } = (
        $in_progress       ? 1 : 0,
        $process_is_active ? 0 : 1,
    );

    return;
}

sub purge_old_logs {
    my ($class) = @_;

    Cpanel::Context::must_not_be_scalar();

    my $dir = $class->_DIR();

    my @unlinked;

    Cpanel::Autodie::exists($dir);
    if ( -d _ ) {

        #This doesn’t use _get_isotime() so that tests will
        #(correctly) discard things that were mock-created
        #in the past.
        my $ttl_boundary = Cpanel::Time::ISO::unix2iso( time - $Cpanel::SSL::Auto::Constants::LOG_TTL );

        Cpanel::FileUtils::Read::for_each_directory_node(
            $dir,
            sub {
                return if !m<\A$log_entry_dirname_regexp\z>xo;
                my $start_time = $1;
                return if $start_time gt $ttl_boundary;

                #Rename it first so that get_catalog() doesn’t see
                #a partial log entry.
                Cpanel::Autodie::rename( "$dir/$start_time", "$dir/.purge.$start_time" );

                my %attrs = ( start_time => $start_time );
                for my $a (qw( upid provider username )) {
                    try {
                        $attrs{$a} = Cpanel::Autodie::readlink_if_exists("$dir/.purge.$start_time/$a");
                        $class->_augment_log_entry_with_process_data( \%attrs );
                    }
                    catch {
                        if ( !try { $_->error_name() eq 'ENOENT' } ) {
                            warn Cpanel::Exception::get_string($_);    #should not happen
                        }

                        $attrs{$a} = undef;
                    };
                }

                require File::Path;
                File::Path::remove_tree("$dir/.purge.$start_time");

                push @unlinked, \%attrs;
            },
        );
    }

    return @unlinked;
}

#----------------------------------------------------------------------

sub info {
    return $_[0]->{'_output'}->info( $_[1] );
}

sub warn {
    return $_[0]->{'_output'}->warn( $_[1] );
}

sub error {
    return $_[0]->{'_output'}->error( $_[1] );
}

sub success {
    return $_[0]->{'_output'}->success( $_[1] );
}

sub new {
    my ( $class, %opts ) = @_;

    my $provider = $opts{'provider'};

    #We shouldn’t create or update a log entry for a nonexistent provider.
    if ( length $provider ) {
        Cpanel::SSL::Auto::Utils::provider_exists_or_die($provider);
    }

    my $self = {
        _pid      => $$,
        _provider => $provider,
    };
    bless $self, $class;

    my $base_dir      = $self->_DIR();
    my $existing_time = $opts{'start_time'};
    if ( length $existing_time ) {
        Cpanel::Validate::Time::iso_or_die( $opts{'start_time'} );
    }
    else {
        $self->{'_start_epoch'} = time;
        $opts{'start_time'} = $self->_get_isotime( $self->{'_start_epoch'} );
    }

    my $filename_base = $opts{'start_time'};

    my @sysopen_flags = qw(O_WRONLY O_APPEND);

    my $filename_prefix = rand . '.';

    #For new log entries, we have some thing to set up:
    if ( !$existing_time ) {
        substr( $filename_base, 0, 0, $filename_prefix );

        #First create the directory.
        Cpanel::Mkdir::ensure_directory_existence_and_mode(
            "$base_dir/$filename_base",
            0700,
        );

        # We *used* to write the “in_progress” flag here. Instead
        # we now write the UPID (cf. Cpanel::UPID) so that we can
        # distinguish between AutoSSL runs that finished but are
        # “left open” (e.g., cPanel provider and there are pending
        # certs) versus ones where the AutoSSL run itself is unfinished.
        Cpanel::Autodie::symlink( Cpanel::UPID::get($$), "$base_dir/$filename_base/upid" );

        #Store the username.
        my $username = $opts{'username'} || '*';
        Cpanel::Autodie::symlink( $username, "$base_dir/$filename_base/username" );

        #Store the provider name.
        Cpanel::Autodie::symlink( $provider, "$base_dir/$filename_base/provider" );

        #We’ll need to create the file.
        push @sysopen_flags, qw(O_EXCL O_CREAT);
    }

    my @exts = qw(json txt);
    my %fh   = map { $_ => undef } @exts;

    try {
        for my $ext (@exts) {
            Cpanel::Autodie::sysopen(
                $fh{$ext},
                "$base_dir/$filename_base/$ext",
                Cpanel::Fcntl::or_flags(@sysopen_flags),
                0600,
            );
        }
    }
    catch {
        if ( try { $_->isa('Cpanel::Exception::IO::FileOpenError') } ) {
            if ( $_->error_name() eq 'ENOENT' ) {
                die Cpanel::Exception::create( 'AutoSSL::LogNotFound', [ start_time => $opts{'start_time'} ] );
            }
        }

        local $@ = $_;
        die;
    };

    #We created the directory as a temp directory; now that it’s
    #all set up correctly, move it into place.
    if ( !$existing_time ) {

        # case CPANEL-11955: If two AutoSSL runs start in the same clock
        # second (e.g., for two different users) then we need to find
        # another available log file name.
        # Since they are time indexed we are left with little option except
        # to abuse the system by jumping the start_time into the future
        # until we find a free filename. This avoids the need to
        # redesign the system to handle a rare corner case.
        #
        # In practice this should not cause a problem or even be
        # noticed because it’s such a rare event. We use a similar
        # solution for writing zone files to ensure that bind can pick
        # them up with Cpanel::File::Transaction::Base’s minimum_mtime
        # flag.

        my $renamed;

        my $iterations = 0;

        while ( !$renamed ) {
            try {
                $renamed = Cpanel::Autodie::rename(
                    "$base_dir/$filename_base",
                    "$base_dir/$opts{'start_time'}",
                );
            }
            catch {
                if ( $_->error_name() eq 'EEXIST' || $_->error_name() eq 'ENOTEMPTY' ) {
                    $iterations++;

                    if ( $iterations > $MAX_ATTEMPTS_TO_CREATE_UNIQUE_LOG_NAME ) {
                        die "The system failed to create a unique AutoSSL log for ($opts{'username'}) in “$base_dir” after “$MAX_ATTEMPTS_TO_CREATE_UNIQUE_LOG_NAME” attempts. This should rarely (if ever?) happen; if you find that it happens frequently, please report this to cPanel.";
                    }

                    $opts{'start_time'} = $self->_get_isotime( $iterations + $self->{'_start_epoch'} );
                }
            };
        }
    }

    $self->{'_start_time'} = $opts{'start_time'};

    my @outputs = (
        Cpanel::SSL::Auto::Log::Output->new(
            filehandle       => $fh{'txt'},
            timestamp_method => $self->can('_get_isotime'),
        ),
        Cpanel::Output::TimeStamp->new(
            filehandle       => $fh{'json'},
            timestamp_method => $self->can('_get_isotime'),
        ),
    );

    if ( _terminal_ok() ) {
        push @outputs, Cpanel::Output::Formatted::Terminal->new( filehandle => \*STDOUT );
    }

    $self->{'_output'} = Cpanel::Output::Multi->new( output_objs => \@outputs );

    return $self;
}

sub create_indent_guard ($self) {
    return $self->{'_output'}->create_indent_guard();
}

sub increase_indent_level {
    my ( $self, @args ) = @_;
    return $self->{'_output'}->increase_indent_level(@args);
}

sub decrease_indent_level {
    my ( $self, @args ) = @_;
    return $self->{'_output'}->decrease_indent_level(@args);
}

sub get_start_time {
    my ($self) = @_;

    return $self->{'_start_time'};
}

sub set_in_progress {
    my ($self) = @_;

    my $path = $self->_DIR() . "/$self->{'_start_time'}/in_progress";

    Cpanel::Autodie::symlink_if_no_conflict( 1, $path );

    return;
}

sub set_completed {
    my ($self) = @_;

    my $path = $self->_DIR() . "/$self->{'_start_time'}/in_progress";

    return Cpanel::Autodie::unlink_if_exists($path);
}

#mocked in tests
sub _terminal_ok { return -t \*STDIN }

#mocked in tests
my $_last_time = -1;
my $_last_iso_time;

sub _get_isotime {
    my ( $self, $time ) = @_;
    $time ||= time();

    # Memorize iso time: If its the same second as the last log message only calculate it once
    return $_last_iso_time if $_last_time == $time;
    $_last_time = $time;
    return ( $_last_iso_time = Cpanel::Time::ISO::unix2iso($time) );
}

#----------------------------------------------------------------------

package Cpanel::SSL::Auto::Log::Output;

use Cpanel::Output ();

use parent qw(
  Cpanel::Output::Formatted::TimeStamp
  Cpanel::Output::Formatted::Plain
);

use constant INDENT_AFTER_PREPEND => 1;

sub message {
    my ( $self, $message_type, $msg_contents, $source, $partial_message ) = @_;

    return $self->SUPER::message(
        $message_type,
        $msg_contents,
        $source,
        $partial_message,
        $Cpanel::Output::PREPENDED_MESSAGE,
    );
}

sub _prepend_message {
    my ( $self, @args ) = @_;

    return substr( $self->SUPER::_prepend_message(@args), 0, -1 );
}

sub _indent {
    my ($self) = @_;

    return $self->SUPER::_indent() || q< >;
}

1;
