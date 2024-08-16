package Cpanel::OSCAR;

# cpanel - Cpanel/OSCAR.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A bare-bones OSCAR (ICQ) client that serves cPanel and WHM’s needs
# with these services over SSL/TLS.
#
# We previously used Net::OSCAR which, as of 2015, does not support SSL/TLS.
# It also hasn’t been updated since 2006 and is kind of weird to use/mock.
#
# This is stitched together from the APIs described here:
#
# http://web.archive.org/web/20090218224837/http://dev.aol.com/aim/web/serverapi_reference
# http://web.archive.org/web/20080309233919/http://dev.aol.com/authentication_for_clients
#
# ...and from libpurple/protocols/oscar/clientlogin.c in libpurple.
#
# Use:
#
#   #This creates an appropriate subclass instance
#   #based on whether $screenname looks like it’s for AIM or ICQ.
#   my $oscar = Cpanel::OSCAR->create($screenname);
#
#   print $oscar->get_service_name();
#
#   $oscar->send_message( $password, $recipient, $message );
#
# “action” methods just return the object,
# so you can also “chain” the calls, like:
#
#   Cpanel::OSCAR->create(..)->send_message(..)->send_message(..);
#
# A failure at any step of the way throws an exception.
#
# This will cache the login credentials (i.e., from the “clientLogin” call)
# and reuse them as long as they are still valid. This reduces the likelihood
# of being rate-limited.
#
# NOTE: Does this need a logout() method? It seems unnecessary.
# NOTE: AIM has a death notice for Dec 15 2017. Only ICQ uses OSCAR past then.
#----------------------------------------------------------------------

use strict;

use Digest::SHA ();
use Encode      ();

use Try::Tiny;

use Cpanel::Base64           ();
use Cpanel::Encoder::URI     ();
use Cpanel::Exception        ();
use Cpanel::HTTP::Client     ();
use Cpanel::JSON             ();
use Cpanel::LoadFile         ();
use Cpanel::OSCAR::Signing   ();
use Cpanel::PwCache          ();
use Cpanel::FileUtils::Write ();

#for testing
our @_HTTP_CLIENT_ARGS;

my $TIMEOUT_PADDING = 60;

my %URL = (
    login   => '/auth/clientLogin',
    session => '/aim/startSession',
    sendim  => '/im/sendIM',
);

#We’re stealing this from libpurple. AOL doesn’t give these out anymore,
#so this is pretty much what we have to do.
#
#https://hg.pidgin.im/pidgin/main/file/d1c41298bacd/libpurple/protocols/oscar/clientlogin.c
#
my $LIBPURPLE_DEV_ID = 'ma15d7JTxbmVG-RP';

#----------------------------------------------------------------------

#This is called create() rather than new()
#because it creates instances of subclasses.
#
#NOTE: We don't accept password here in order to avoid storing
#private information in the object.
#This alleviates some risk of stack traces etc. showing them.
#
sub create {
    my ( $class, $screenname ) = @_;

    my $service = 'ICQ';

    my $self = {
        _screenname => $screenname,
        _service    => $service,
        _http       => Cpanel::HTTP::Client->new(@_HTTP_CLIENT_ARGS),
    };

    return bless $self, "${class}::$service";
}

sub get_service_name {
    my ($self) = @_;

    return $self->{'_service'};
}

sub send_message {
    my ( $self, $password, $recipient, $message ) = @_;

    $self->_setup_credentials($password);

    $self->_get_new_session();

    #NOTE: AOL’s API docs seem to imply that this call should
    #work without a session, but it didn’t work without
    #having called startSession and passing in “aimsid”.
    $self->_signed_post(
        'sendim',
        {
            f       => 'json',
            a       => $self->{'_credentials'}{'a'},
            aimsid  => $self->{'_session'}{'aimsid'},
            ts      => $self->{'_credentials'}{'hostTime'},
            t       => $recipient,
            message => Encode::decode_utf8($message),
        },
    );

    return $self;
}

#----------------------------------------------------------------------

#overridden in tests
sub _credentials_file_dir {
    return Cpanel::PwCache::gethomedir() . '/.cpanel';
}

sub _credentials_file_name {
    my ( $self, $password ) = @_;

    return sprintf(
        "%s/%s_%s_%s.json",
        _credentials_file_dir(),
        $self->{'_service'},
        $self->{'_screenname'},
        Digest::SHA::sha512_hex("$self->{'_screenname'}/$password"),
    );
}

sub _load_stored_credentials {
    my ( $self, $password ) = @_;

    my $credentials_file = $self->_credentials_file_name($password);

    my $credentials_hr;
    try {
        my $json = Cpanel::LoadFile::load($credentials_file);
        $credentials_hr = Cpanel::JSON::Load($json);
    }
    catch {

        #Warn only if the file exists since that indicates corruption,
        #which could indicate a larger problem.

        my $warn = !try { $_->isa('Cpanel::Exception::IO::FileNotFound') };

        if ($warn) {
            warn "Ignored stored credentials file “$credentials_file” because of an error: " . $_->to_string();
        }
    };

    return $credentials_hr ? %$credentials_hr : ();
}

sub _save_credentials {
    my ( $self, $password ) = @_;

    my $credentials_file = $self->_credentials_file_name($password);

    my $json = Cpanel::JSON::Dump( $self->{'_credentials'} );

    try {
        Cpanel::FileUtils::Write::overwrite(
            $credentials_file,
            $json,
        );
    }
    catch {
        warn "Failed to save credentials file “$credentials_file” because of an error: " . $_->to_string();
    };

    return;
}

sub _get_new_credentials {
    my ( $self, $password ) = @_;

    my $login_hr = $self->_do_post(
        'login',
        {
            devId => $LIBPURPLE_DEV_ID,
            f     => 'json',
            s     => $self->{'_screenname'},
            pwd   => $password,
        },
    );

    my $cdata = $login_hr->{'data'};

    my $token_a = Cpanel::Encoder::URI::uri_decode_str( $cdata->{'token'}{'a'} );

    my $secret = $cdata->{'sessionSecret'};

    my $secret_hash = _pad_base64( Digest::SHA::hmac_sha256_base64( $secret, $password ) );

    my $expire_time = $cdata->{'hostTime'} + $cdata->{'token'}{'expiresIn'};

    $self->{'_credentials'} = {
        a           => $token_a,
        hostTime    => $cdata->{'hostTime'},
        expire_time => $expire_time,
        secret_hash => $secret_hash,

        #These are for debugging.
        expire_time_utc => scalar gmtime $expire_time,
        hostTime_utc    => scalar gmtime $cdata->{'hostTime'},
    };

    return;
}

sub _get_new_session {
    my ($self) = @_;

    my $session_hr = $self->_signed_post(
        'session',
        {
            f      => 'json',
            k      => $LIBPURPLE_DEV_ID,
            a      => $self->{'_credentials'}{'a'},
            ts     => $self->{'_credentials'}{'hostTime'},
            events => 'im',                                  #an arbitrary event
        },
    );

    my $sdata = $session_hr->{'data'};

    $self->{'_session'} = {
        aimsid => $sdata->{'aimsid'},

        #NOTE: As of testing in August 2015, the “sessionTimeout” from
        #AIM was 30 seconds, as a result of which we will always
        #ask for a new session whenever we send a message. This is in
        #place, though, in case that was a matter of rate-limiting.
        sessionTimeout => $sdata->{'myInfo'}{'self'}{'sessionTimeout'},
    };

    return;
}

sub _setup_session {
    my ($self) = @_;

    my $sdata = $self->{'_session'};
    return if $sdata && $sdata->{'sessionTimeout'} > time + $TIMEOUT_PADDING;

    return $self->_get_new_session();
}

sub _setup_credentials {
    my ( $self, $password ) = @_;

    #Assume that what we’re about to do will take a bit of time,
    #so treat “about-to-expire” credentials as expired.
    my $min_stored_expire_time = time + $TIMEOUT_PADDING;

    if ( $self->{'_credentials'} ) {
        my $in_memory_expire_time = $self->{'_credentials'}{'expire_time'};
        return if $in_memory_expire_time < $min_stored_expire_time;
    }

    my %loaded = (
        expire_time => 0,
        $self->_load_stored_credentials($password),
    );

    my $expired = ( $loaded{'expire_time'} < ( time + 60 ) );

    if ($expired) {
        $self->_get_new_credentials($password);
        $self->_save_credentials($password);
    }
    else {
        $self->{'_credentials'} = \%loaded;
    }

    return;
}

*_pad_base64 = \&Cpanel::Base64::pad;

sub _build_url_from_key {
    my ( $self, $url_key ) = @_;

    my $server = ( $url_key eq 'login' ) ? $self->_LOGIN_HOST() : $self->_API_HOST();

    return "https://$server$URL{$url_key}";
}

sub _do_post {
    my ( $self, $url_key, $params_hr ) = @_;

    my $url = $self->_build_url_from_key($url_key);

    my $post = $self->{'_http'}->post_form( $url, $params_hr );

    if ( !$post->{'success'} ) {
        $self->_die_with_post($post);
    }

    my $content = Cpanel::JSON::Load( $post->content() );

    if ( $content->{'response'}{'statusCode'} != 200 ) {
        $self->_die_with_post($post);
    }

    return $content->{'response'};
}

sub _die_with_post {
    my ( $self, $post ) = @_;

    die Cpanel::Exception::create(
        'OSCARWeb',
        {
            service  => $self->{'_service'},
            username => $self->{'_screenname'},
            response => $post,
        }
    );
}

sub _signed_post {
    my ( $self, $url_key, $params_hr ) = @_;

    my $url_for_hash = $self->_build_url_from_key($url_key);

    my $digest = Cpanel::OSCAR::Signing::get_base_string(
        'POST',
        $url_for_hash,
        $params_hr,
        $self->{'_credentials'}{'secret_hash'},
    );

    return $self->_do_post(
        $url_key,
        {
            %$params_hr,
            sig_sha256 => $digest,
        },
    );
}

#----------------------------------------------------------------------

package Cpanel::OSCAR::ICQ;

use parent qw(
  Cpanel::OSCAR
);

our $LOGIN_HOST = 'api.login.icq.net';
our $API_HOST   = 'api.icq.net';

sub _LOGIN_HOST {
    return $LOGIN_HOST;
}

sub _API_HOST {
    return $API_HOST;
}

1;
