package Whostmgr::API::1::iContact;

# cpanel - Whostmgr/API/1/iContact.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::API::1::Utils ();

use Encode ();

use Cpanel::DIp::MainIP ();
use Cpanel::Exception   ();
use Cpanel::Hostname    ();
use Cpanel::LoadModule  ();
use Cpanel::Locale      ();

use constant NEEDS_ROLE => {
    send_test_posturl         => undef,
    send_test_pushbullet_note => undef,
    verify_icq_access         => undef,
    verify_oscar_access       => undef,
    verify_posturl_access     => undef,
    verify_pushbullet_access  => undef,
    verify_slack_access       => undef,
};

use Try::Tiny;

#exposed for testing
our $_OSCAR_CLASS      = 'Cpanel::OSCAR';
our $_PUSHBULLET_CLASS = 'Cpanel::Pushbullet';
our $_POSTURL_CLASS    = 'Cpanel::Posturl';
our $_SLACK_CLASS      = 'Slack::WebHook';

#----------------------------------------------------------------------
# Sends a single Pushbullet message. This does not confirm receipt; the
# user/caller must do that manually.
#
# Inputs (required):
#   access_token
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
#   payload     The payload from the Pushbullet server’s API.
#
sub send_test_pushbullet_note {
    my ( $args, $metadata ) = @_;

    my $token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'access_token' );

    Cpanel::LoadModule::load_perl_module($_PUSHBULLET_CLASS);

    my $message_id = _generate_message_id();

    my $hostname  = Cpanel::Hostname::gethostname();
    my $server_ip = Cpanel::DIp::MainIP::getmainserverip();

    my $body = _locale()->maketext( "This message confirms that “[_1]” ([_2]) can send a message to you via [asis,Pushbullet].", $hostname, $server_ip );

    my $pb      = $_PUSHBULLET_CLASS->new( access_token => $token );
    my $payload = $pb->push_note(
        title => _generate_subject($message_id),
        body  => _add_timestamp($body),
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        message_id => $message_id,
        payload    => $payload,
    };
}

#----------------------------------------------------------------------
# Sends a single Slack message. This does not confirm receipt; the
# user/caller must do that manually.
#
# Inputs (required):
#   slack_url
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
#   payload     The payload from the Slack API.
#
sub send_test_slack_message {
    my ( $args, $metadata ) = @_;

    my $token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'slack_url' );

    Cpanel::LoadModule::load_perl_module($_SLACK_CLASS);

    my $message_id = _generate_message_id();

    my $hostname  = Cpanel::Hostname::gethostname();
    my $server_ip = Cpanel::DIp::MainIP::getmainserverip();

    my $body = _locale()->maketext( "This message confirms that “[_1]” ([_2]) can send a message to you via Slack.", $hostname, $server_ip );

    my $subject = _generate_subject($message_id);
    $body = _add_timestamp($body);

    $subject = Encode::decode_utf8( $subject, Encode::FB_QUIET );
    $body    = Encode::decode_utf8( $body,    Encode::FB_QUIET );

    my $pb      = $_SLACK_CLASS->new( url => $token );
    my $payload = $pb->post_ok(
        title => $subject,
        text  => $body,
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        message_id => $message_id,
        payload    => $payload,
    };
}

#----------------------------------------------------------------------
# Sends a post to a url using Cpanel::Posturl. This does not confirm receipt; the
# user/caller must do that manually.
#
# Inputs (required):
#   url
#   args
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
#   payload     Returns a hashref from a HTTP::Tiny::request call
#               cf. https://metacpan.org/pod/HTTP::Tiny#request
#
sub send_test_posturl {
    my ( $args, $metadata ) = @_;

    my $url = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'url' );

    Cpanel::LoadModule::load_perl_module($_POSTURL_CLASS);
    Cpanel::LoadModule::load_perl_module('Encode');

    my $message_id = _generate_message_id();

    my $hostname  = Cpanel::Hostname::gethostname();
    my $server_ip = Cpanel::DIp::MainIP::getmainserverip();

    my $body         = _locale()->maketext( "This message confirms that “[_1]” ([_2]) can send a message to you via [asis,Posturl].", $hostname, $server_ip );
    my $decoded_body = Encode::decode_utf8( $body, Encode::FB_QUIET() );

    my $pb = $_POSTURL_CLASS->new();

    my ( $payload, $err );
    try {
        $payload = $pb->post(
            $url,
            {
                subject => _generate_subject($message_id),
                body    => _add_timestamp($decoded_body),
            }
        );
    }
    catch {
        $err = $_;
    };

    my $ret = {
        message_id => $message_id,
        payload    => $payload,
    };

    if ( $payload->{'success'} && !$err ) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $payload->{'reason'};
        $ret->{'error'}       = $err ? Cpanel::Exception::get_string($err) : $payload->{'content'} || $payload->{'reason'};
    }
    return $ret;
}

sub _generate_message_id {

    #A simple ID is generated because this will be used
    #for visual comparison by an end user between devices.
    #
    #NOTE: no 0 nor O, so we don't confuse user
    #
    my @chars = (
        "A" .. "N",
        "P" .. "Z",
        "1" .. "9",
    );

    my $message_id;
    $message_id .= $chars[ rand @chars ] for 1 .. 4;

    return $message_id;
}

sub _add_timestamp {
    my ($msg) = @_;

    return "$msg\n\n" . _locale()->maketext( "This message was sent on [datetime,_1,date_format_full] at [datetime,_1,time_format_full].", time );
}

sub _generate_subject {
    my ($message_id) = @_;

    return _locale()->maketext( 'Test message (ID: [_1])', $message_id );
}

my $_locale;

sub _locale {
    return $_locale ||= Cpanel::Locale->get_handle();
}

#----------------------------------------------------------------------
# Sends a single OSCAR message.
#
# Inputs (all required):
#   username
#   password
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
sub verify_oscar_access {
    my ( $args, $metadata ) = @_;

    my @req = qw(
      username
      password
    );

    my %opts;
    for (@req) {
        $opts{$_} = Whostmgr::API::1::Utils::get_length_required_argument( $args, $_ );
    }

    return _send_oscar_message_to_recipient(
        $metadata,
        @opts{qw( username  password  username )},
    );
}

#Overridden in tests
sub _send_oscar_message_to_recipient {
    my ( $metadata, $username, $password, $recipient ) = @_;

    my $hostname  = Cpanel::Hostname::gethostname();
    my $server_ip = Cpanel::DIp::MainIP::getmainserverip();

    require Cpanel::OSCAR;    # PPI USE OK - used below this line
    my $oscar   = $_OSCAR_CLASS->create($username);
    my $service = $oscar->get_service_name();
    my $body;

    if ( $username eq $recipient ) {
        $body = _locale()->maketext( "This message confirms that “[_1]” can log in to the chat service from “[_2]” ([_3]) and send a message.", $username, $hostname, $server_ip );
    }
    else {
        $body = _locale()->maketext( "This message confirms that “[_1]” can log in to the chat service from “[_2]” ([_3]) and send a message to “[_4]”.", $username, $hostname, $server_ip, $recipient );
    }

    my $message_id = _generate_message_id();

    $oscar->send_message(
        $password,
        $username,
        _generate_subject($message_id) . "\n\n" . _add_timestamp($body)
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        message_id => $message_id,
    };
}

sub _basic_setup_name {
    return _locale()->maketext('Basic [asis,cPanel amp() WHM] Setup');
}

sub _verify_oscar_via_wwwacctconf {
    my ( $metadata, $service_name, $user_param, $pw_param, $recp_param ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadWwwAcctConf');

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    if ( grep { !length $wwwacct_ref->{$_} } $user_param, $pw_param, $recp_param ) {
        die Cpanel::Exception->create( 'The “[_1]” service is not configured completely. To fix this issue, go to “[_2]” in the WHM menu. Then, enter a username, password, and recipient. Finally, try this action again.', [ $service_name, _basic_setup_name() ] );
    }

    return _send_oscar_message_to_recipient(
        $metadata,
        @{$wwwacct_ref}{ $user_param, $pw_param, $recp_param },
    );
}

#----------------------------------------------------------------------
# Fetches system access info then tests that access works to ICQ
#
# No inputs
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
sub verify_icq_access {
    my ( $args, $metadata ) = @_;

    return _verify_oscar_via_wwwacctconf(
        $metadata,
        'ICQ',
        qw( ICQUSER  ICQPASS  CONTACTUIN ),
    );
}

#----------------------------------------------------------------------
# Fetches system access info then tests that access works to pushbullet
#
# No inputs
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
sub verify_pushbullet_access {
    my ( $args, $metadata ) = @_;
    require Cpanel::Config::LoadWwwAcctConf;

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    my @pushbullet_keys = split( ',', $wwwacct_ref->{'CONTACTPUSHBULLET'} );

    my @results;

    foreach my $key (@pushbullet_keys) {
        try {
            my $result = Whostmgr::API::1::iContact::send_test_pushbullet_note(
                {
                    access_token => $key,
                },
                $metadata
            );
            push @results,
              {
                access_token => $key,
                result       => $result
              };
        }
        catch {
            push @results,
              {
                access_token => $key,
                result       => { error => $_ }
              };
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        results => \@results,
    };
}

#----------------------------------------------------------------------
# Fetches system access info then tests that access works to Slack
#
# No inputs
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
sub verify_slack_access {
    my ( $args, $metadata ) = @_;
    require Cpanel::Config::LoadWwwAcctConf;

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    my @webhook_urls = split( ',', $wwwacct_ref->{'CONTACTSLACK'} );

    my @results;

    foreach my $webhook_url (@webhook_urls) {
        try {
            my $result = Whostmgr::API::1::iContact::send_test_slack_message(
                {
                    slack_url => $webhook_url,
                },
                $metadata
            );
            push @results,
              {
                url    => $webhook_url,
                result => $result
              };
        }
        catch {
            push @results,
              {
                url    => $webhook_url,
                result => { error => $_ }
              };
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        results => \@results,
    };
}

#----------------------------------------------------------------------
# Fetches system access info then tests that access works to posturl
#
# No inputs
#
# Returns a single hashref of:
#
#   message_id  An ID string included in the message that the operator
#               can use to identify the message.
#
sub verify_posturl_access {
    my ( $args, $metadata ) = @_;
    require Cpanel::Config::LoadWwwAcctConf;

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    my @posturl_keys = split( ',', $wwwacct_ref->{'CONTACTPOSTURL'} );

    my @results;

    foreach my $key (@posturl_keys) {
        try {
            my $result = Whostmgr::API::1::iContact::send_test_posturl(
                {
                    url => $key,
                },
                $metadata
            );
            push @results,
              {
                url    => $key,
                result => $result
              };
        }
        catch {
            push @results,
              {
                url    => $key,
                result => { error => $_ }
              };
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        results => \@results,
    };

}

1;
