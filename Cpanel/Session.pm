package Cpanel::Session;

# cpanel - Cpanel/Session.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant { _EEXIST => 17 };

use Cpanel::ConfigFiles          ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Config::FlushConfig  ();
use Cpanel::Config::Session      ();
use Cpanel::Fcntl::Constants     ();
use Cpanel::SafeFile             ();
use Cpanel::Session::Get         ();
use Cpanel::Session::Encoder     ();
use Cpanel::Session::Load        ();
use Cpanel::FileUtils::Write     ();
use Cpanel::Rand::Get            ();
use Cpanel::SV                   ();

our $VERSION             = 2.2;
our $MAX_CREATE_ATTEMPTS = 400;

my $OB_SECRET_LENGTH = 16;

our $token_prefix    = 'cpsess';
our $token_strip_end = '___';

{
    no warnings 'once';
    *loadSession                   = *Cpanel::Session::Load::loadSession;
    *get_ob_part                   = *Cpanel::Session::Load::get_ob_part;
    *get_session_file_path         = *Cpanel::Session::Load::get_session_file_path;
    *is_valid_session_name         = *Cpanel::Session::Load::is_valid_session_name;
    *session_exists                = *Cpanel::Session::Load::session_exists;
    *session_exists_and_is_current = *Cpanel::Session::Load::session_exists_and_is_current;
}

# --- Object methods ----

#Parameters:
#
#   log_obj  (optional) A Cpanel::Logger object. If not given, we send to
#           [$Cpanel::root/logs/session_log].
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {};

    if ( !$OPTS{'log_obj'} ) {
        require Cpanel::Logger;
        $self->{'log_obj'} = Cpanel::Logger->new( { 'alternate_logfile' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/session_log' } ) or die "Could not open session_log: $!";
    }
    else {
        $self->{'log_obj'} = $OPTS{'log_obj'};
    }

    create_dirs_if_needed();

    bless $self, $class;

    return $self;
}

#NOTE: This is a SETTER, not a GETTER.
#
sub set_log_obj {
    my ( $self, $obj ) = @_;

    $self->{'log_obj'} = $obj;

    return 1;
}

sub purge {
    my ( $self, $session, $reason, $faillog ) = @_;
    require Cpanel::Session::SinglePurge;
    return Cpanel::Session::SinglePurge::purge_session( $session, $reason, $self->{'log_obj'}, $faillog );
}

#Parameters:
#   user        The username (email address for webmail session)
#
#   tag         Passed, along with the "user", to Cpanel::Session::Get::getsessionname()
#
#   session     A hashref that contains various information about the session
#               "session" keys that this code cares about specifically are:
#                   origin
#                   user
#                   login_theme
#                   theme
#                   lang
#                   pass
#                   needs_auth
#               ...however, the entire hashref is saved (via saveSession) to disk.
#
sub create {
    my ( $self, %OPTS ) = @_;

    my $user = $OPTS{'user'};

    if ( !$OPTS{'session'} ) {
        die __PACKAGE__ . "::create requires a session reference";
    }

    # CPANEL-16490
    #
    # We shallow clone session and the origin hashref
    # in order to avoid anything that will change the utf-8 flags
    # since perl will do the right thing.
    #
    my $uncopied_session = $OPTS{'session'};

    # Shallow clone if origin keys
    my $origin_data_copy = ref $uncopied_session->{'origin'} ? { %{ $uncopied_session->{'origin'} } } : undef;
    $origin_data_copy ||= { 'app' => $0, 'method' => join( ":", ( caller() )[ 1, 0 ] ) };

    # Now reassemble into $session_ref which is
    # our clone of $OPTS{'session'}
    my $session_ref = { %{$uncopied_session} };
    $session_ref->{'origin'} = $origin_data_copy;

    my $tag = $OPTS{'tag'};

    filter_sessiondata($session_ref);

    $user ||= '';

    my $safety_count = 0;
    my $randsession;

    while ( $safety_count++ < $MAX_CREATE_ATTEMPTS ) {
        $randsession = Cpanel::SV::untaint( Cpanel::Session::Get::getsessionname( $user, $tag ) );

        $randsession .= _generate_ob_part();

        encode_origin($session_ref);

        if ( saveSession( $randsession, $session_ref, 'initial' => 1 ) ) {
            if ( $user && $session_ref->{'origin_as_string'} ) {
                my $host               = ( $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'} || 'internal' );
                my $obfree_randsession = $randsession;
                get_ob_part( \$obfree_randsession );    # strip obpart for log
                my $entry = qq{$host NEW $obfree_randsession $session_ref->{'origin_as_string'}};
                $self->{'log_obj'}->info($entry);
            }
            return $randsession;
        }
    }
    return undef;
}

# --- Direct methods ----

sub saveSession {
    my ( $session, $session_ref, %options ) = @_;

    # sanity checks #

    die 'you must call saveSession with the session argument'
      if !defined $session || !$session;

    # process optional parameters #

    my $initial   = defined $options{'initial'}   ? $options{'initial'}   : 0;
    my $overwrite = defined $options{'overwrite'} ? $options{'overwrite'} : 1;

    # pull apart the session if necessary #

    my $ob = get_ob_part( \$session );
    return 0 if !is_valid_session_name($session);

    # session possibly includes a password, we want to replace the cleartext password to an obfuscated one #
    my $encoder = $ob && Cpanel::Session::Encoder->new( 'secret' => $ob );

    local $session_ref->{'pass'} = $encoder->encode_data( $session_ref->{'pass'} )
      if $encoder && length $session_ref->{'pass'};

    # we need to lock the rest of this function as it not only flushes out the config, it writes a preauth "flag file" and does caching operations #
    # ... so compute the session file #
    my $session_file = get_session_file_path($session);

    my $sysopen_flags = $Cpanel::Fcntl::Constants::O_RDWR;
    if ( $initial || !$overwrite ) {
        $sysopen_flags |= $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL;
    }

    my $session_fh;
    my $lockref = Cpanel::SafeFile::safesysopen( $session_fh, $session_file, $sysopen_flags, 0600 );

    if ( !$lockref ) {
        return 0 if ( !$overwrite && $! == _EEXIST() );
        die "The system failed to open the session file “$session_file” because of an error: $!";
    }

    my $result = write_session( $session, $session_fh, $session_ref, $overwrite );

    # release the lockfile if we opened it earlier #
    Cpanel::SafeFile::safeunlock($lockref) if $lockref;

    return $result;
}

sub write_session {
    my ( $session, $session_fh, $session_ref ) = @_;

    # need to feed arguments for flush as we do not have an existing hand
    # note: write functionality in the product have a non-positive overwrite argument #
    my $flush_result = Cpanel::Config::FlushConfig::flushConfig( $session_fh, $session_ref, '=', undef, { 'perms' => 0600 } );
    return $flush_result if !$flush_result;

    # we'll do the auth logic and caching stuff only if the flush_result was good, otherwise we just assign the overall_result and fall through to the cleanup #
    if ( $session_ref->{'needs_auth'} ) {
        unless ( -e $Cpanel::Config::Session::SESSION_DIR . '/preauth/' . $session ) {
            if ( open my $preauth_fh, '>', $Cpanel::Config::Session::SESSION_DIR . '/preauth/' . $session ) {
                print $preauth_fh ( $main::now || time() );
                close $preauth_fh;
            }
        }
    }
    elsif ( -e $Cpanel::Config::Session::SESSION_DIR . '/preauth/' . $session ) {
        unlink $Cpanel::Config::Session::SESSION_DIR . '/preauth/' . $session;
    }

    Cpanel::FileUtils::Write::overwrite(
        "$Cpanel::Config::Session::SESSION_DIR/cache/$session",
        Cpanel::AdminBin::Serializer::Dump($session_ref),
        0600,
    );

    return 1;
}

sub create_dirs_if_needed {
    mkdir( $Cpanel::Config::Session::SESSION_DIR, 0700 ) if ( !-d $Cpanel::Config::Session::SESSION_DIR );
    foreach my $subdir ( 'cache', 'preauth', 'raw' ) {
        mkdir( $Cpanel::Config::Session::SESSION_DIR . '/' . $subdir, 0700 ) if ( !-d $Cpanel::Config::Session::SESSION_DIR . '/' . $subdir );
    }
    return;
}

sub is_active_security_token_for_user {
    my ( $user, $token ) = @_;

    die "Supplied user is not part of a valid session name" if !is_valid_session_name($user);

    if ( opendir( my $session_dh, $Cpanel::Config::Session::SESSION_DIR . '/raw' ) ) {
        my @sessions_to_check = grep ( m/^\Q$user\E:/ && !m/\.lock$/, readdir($session_dh) );
        foreach my $session (@sessions_to_check) {
            if ( my $sessionRef = Cpanel::Session::Load::loadSession($session) ) {
                return 1 if ( $sessionRef->{'cp_security_token'} && $sessionRef->{'cp_security_token'} eq $token );
            }
        }
    }

    return 0;

}

sub generate_new_security_token {
    return '/' . $token_prefix . sprintf '%010d', ( Cpanel::Rand::Get::getranddata( 10, [ 0 .. 9 ], 10 ) + 1 );
}

# Purge all sessions for user
# input:
#    user - the user to purge
#    reason - why the sessions are being removed
sub purge_user {
    my ( $self, $user, $reason ) = @_;
    require Cpanel::Session::SinglePurge;
    return Cpanel::Session::SinglePurge::purge_user( $user, $reason, $self->{'log_obj'} );
}

sub _generate_ob_part {
    use bytes;
    return ( ',' . unpack( 'h*', Cpanel::Rand::Get::getranddata( $OB_SECRET_LENGTH, [ map { chr } 0 .. 255 ] ) ) );
}

sub encode_origin {
    my ($session_ref) = @_;
    return $session_ref unless ( defined $session_ref && exists $session_ref->{'origin'} );
    $session_ref->{'origin_as_string'} = join( ',', map { "$_=" . ( length $session_ref->{'origin'}{$_} ? $session_ref->{'origin'}{$_} : '' ) } sort keys %{ $session_ref->{'origin'} } ) if ( defined $session_ref->{'origin'} );
    delete $session_ref->{'origin'};
    return $session_ref;
}

sub decode_origin {
    my ($session_ref) = @_;
    return $session_ref unless ( defined $session_ref && exists $session_ref->{'origin_as_string'} );
    $session_ref->{'origin'} = { map { $_ // '' } map { length($_) ? ( split( /=/, $_, 2 ) ) : () } split( /,/, $session_ref->{'origin_as_string'} ) } if ( length $session_ref->{'origin_as_string'} );
    delete $session_ref->{'origin_as_string'};
    return $session_ref;
}

sub filter_sessiondata {
    my ($session_ref) = @_;
    no warnings 'uninitialized';    ## no critic(ProhibitNoWarnings)

    # Prevent manipulation of other entries in session file
    tr{\r\n=\,}{}d for values %{ $session_ref->{'origin'} };

    # Prevent manipulation of other entries in session file
    tr{\r\n}{}d for @{$session_ref}{ grep { $_ ne 'origin' } keys %{$session_ref} };

    # Cleanup possible directory traversal ( A valid 'pass' may have these chars )
    tr{/}{}d for @{$session_ref}{ grep { exists $session_ref->{$_} } qw(user login_theme theme lang) };
    return $session_ref;
}

1;
