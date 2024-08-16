package Cpanel::Server::Handlers::comet;

# cpanel - Cpanel/Server/Handlers/comet.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule        ();
use Cpanel::App               ();
use Cpanel::PwCache           ();
use Cpanel::Server::Constants ();
use Cpanel::SV                ();

use parent 'Cpanel::Server::Handler';

my $COMET_DEBUG                    = 0;
my $cometd_version                 = '1.0';
my $cometd_minimum_version         = '0.9';
my $cometd_supported_connect_types = [ 'long-polling', 'callback-polling' ];
my $comet_soft_keepalive_timeout   = ( 30 * 60 );                              # 30 min - Comet needs a longer soft keepalive timeout
my $comet_hard_keepalive_timeout   = ( 35 * 60 );                              # 35 min - Comet needs a longer soft keepalive timeout

sub handler {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - Refactoring this function is a project not a bug fix
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    my ( $packet, $connection_type );

    Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
    Cpanel::LoadModule::load_perl_module('Cpanel::Comet');

    if ( $ENV{'REQUEST_METHOD'} eq 'GET' ) {
        my $form_ref = $server_obj->timed_parseform(60);
        $server_obj->get_log('error')->info( "[comet_get_event] " . $form_ref->{'message'} ) if $COMET_DEBUG;
        $packet = Cpanel::JSON::Load( $form_ref->{'message'} );
    }
    elsif ( $ENV{'REQUEST_METHOD'} eq 'POST' && $server_obj->request()->get_header('content-type') =~ m{json}i ) {
        my $json = $self->read_content_length_from_socket();
        $packet = Cpanel::JSON::Load($json);
        $server_obj->get_log('error')->info( "[comet_post_event] " . $json ) if $COMET_DEBUG;
    }
    else {
        $server_obj->internal_error('cometd requires json content-type');
    }

    my ( $soft_keepalive_timeout, $hard_keepalive_timeout ) = ( $comet_soft_keepalive_timeout, $comet_hard_keepalive_timeout );
    if ( !$packet || ref $packet ne 'ARRAY' ) {
        $server_obj->internal_error('invalid json received in cometd packet');
    }
    my $document = $server_obj->request()->get_document();

    my $channel = $document;
    $document =~ s/^[.]?\/cometd//;
    local $0 = "$Cpanel::App::appname - answering comet request";
    my $can_send_subscriptions = 1;
    my @comet_stack;
    my $user         = $server_obj->auth()->get_user();
    my $webmailowner = $server_obj->auth()->get_webmailowner();
    my $homedir =
        $> == 0       ? ( $server_obj->{'MEMORIZED'}{'pw_homedir'}{'root'}        ||= Cpanel::PwCache::gethomedir('root') )
      : $webmailowner ? ( $server_obj->{'MEMORIZED'}{'pw_homedir'}{$webmailowner} ||= Cpanel::PwCache::gethomedir($webmailowner) )
      :                 ( $server_obj->{'MEMORIZED'}{'pw_homedir'}{$user}         ||= Cpanel::PwCache::gethomedir($user) );
    Cpanel::SV::untaint($homedir);
    my $most_recent_timeout_value;

    foreach my $event ( @{$packet} ) {

        $most_recent_timeout_value = $event->{'advice'}->{'timeout'} if exists $event->{'advice'}->{'timeout'};

        delete $self->{'cometd'} if ( $event->{'clientId'} && $self->{'cometd'} && $self->{'cometd'}->{'clientId'} ne $event->{'clientId'} );

        $server_obj->get_log('error')->info( "[comet_event] = " . Cpanel::JSON::Dump($event) ) if $COMET_DEBUG;

        if ( $event->{'channel'} eq '/meta/handshake' ) {
            $self->{'cometd'} = Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'}, 'timeout' => $most_recent_timeout_value );
            $can_send_subscriptions = 0;

            # We always shake back.  We should check the supportedConnectionTypes and version and fail
            push @comet_stack,
              {
                ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                'channel'                  => $event->{'channel'},
                'version'                  => $cometd_version,
                'minimumVersion'           => $cometd_minimum_version,
                'supportedConnectionTypes' => $cometd_supported_connect_types,
                'clientId'                 => $self->{'cometd'}->{'clientId'},
                'successful'               => 'true',
                'authSuccessful'           => 'true',
                'advice'                   => { 'reconnect' => 'retry', 'timeout' => $Cpanel::Comet::DEFAULT_BLOCK_TIMEOUT }
              };
        }
        elsif ( $event->{'channel'} eq '/meta/connect' ) {
            $self->{'cometd'} ||= Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'} );
            if ( $self->{'cometd'} ) {
                $connection_type = $event->{'connectionType'};
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'true',
                    'clientId'   => $event->{'clientId'},
                    'error'      => '',
                    'advice'     => { 'reconnect' => 'retry', 'timeout' => $Cpanel::Comet::DEFAULT_BLOCK_TIMEOUT }
                  };

            }
            else {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'false',
                    'clientId'   => $self->{'cometd'}->{'clientId'},
                    'error'      => '500:Invalid clientId:' . $event->{'clientId'},
                    'advice'     => { 'reconnect' => 'none' }
                  };
            }
        }
        elsif ( $event->{'channel'} eq '/meta/disconnect' ) {
            $self->{'cometd'} ||= Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'} );
            $can_send_subscriptions = 0;
            if ( $self->{'cometd'} && $self->{'cometd'}->purgeclient() ) {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'true',
                    'clientId'   => $event->{'clientId'},
                  };
            }
            else {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'false',
                    'clientId'   => $self->{'cometd'}->{'clientId'},
                    'error'      => '500:Invalid clientId:Invalid clientId',
                  };
            }
        }
        elsif ( $event->{'channel'} eq '/meta/subscribe' ) {
            $self->{'cometd'} ||= Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'} );
            my $subscription = $event->{'subscription'};
            $subscription =~ s/\s+//g;
            if ( $self->{'cometd'} && $self->{'cometd'}->subscribe( $subscription, $event->{'position'} ) ) {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'      => $event->{'channel'},
                    'successful'   => 'true',
                    'subscription' => $subscription,
                    'error'        => '',
                    'clientId'     => $self->{'cometd'}->{'clientId'}
                  };
            }
            else {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'      => $event->{'channel'},
                    'successful'   => 'false',
                    'subscription' => $subscription,
                    'error'        => '500:' . $subscription . ':Invalid clientId',
                    'clientId'     => $event->{'clientId'},
                  };
            }
        }
        elsif ( $event->{'channel'} eq '/meta/unsubscribe' ) {
            $self->{'cometd'} ||= Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'} );
            $can_send_subscriptions = 0;
            my $subscription = $event->{'subscription'};
            $subscription =~ s/\s+//g;
            if ( $self->{'cometd'} && $self->{'cometd'}->unsubscribe($subscription) ) {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'      => $event->{'channel'},
                    'successful'   => 'true',
                    'subscription' => $subscription,
                    'error'        => '',
                    'clientId'     => $self->{'cometd'}->{'clientId'},
                  };
            }
            else {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'      => $event->{'channel'},
                    'successful'   => 'false',
                    'subscription' => $subscription,
                    'error'        => '500:' . $subscription . ':Invalid clientId',
                    'clientId'     => $event->{'clientId'},
                  };
            }
        }
        else {
            $self->{'cometd'} ||= Cpanel::Comet->new( 'DEBUG' => $COMET_DEBUG, 'homedir' => $homedir, 'clientId' => $event->{'clientId'} );
            my ( $status, $statusmsg ) = $self->{'cometd'}->add_message(
                $event->{'channel'},

                Cpanel::JSON::Dump(
                    {
                        'data'    => $event->{'data'},
                        'id'      => $event->{'id'},
                        'channel' => $event->{'channel'}
                    }
                )

            );

            if ($status) {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'true',
                    'error'      => '',
                    'clientId'   => $self->{'cometd'}->{'clientId'},
                  };

            }
            else {
                push @comet_stack,
                  {
                    ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                    'channel'    => $event->{'channel'},
                    'successful' => 'false',
                    'error'      => $statusmsg,
                    'clientId'   => $self->{'cometd'}->{'clientId'},
                  };
            }
        }

    }
    if ($can_send_subscriptions) {

        # Connection type is sometimes undefined so we assume callback-polling to preserve legacy behavior
        $connection_type ||= 'callback-polling';
        local $0 = "$Cpanel::App::appname - answering comet request - polling - " . $self->{'cometd'}->{'clientId'};
        my $comet_feeds = $self->{'cometd'}->feed( ( ( !defined $most_recent_timeout_value || $most_recent_timeout_value != 0 ) && $connection_type eq 'long-polling' ) ? 1 : 0 );    #can we block?
        if ( ref $comet_feeds eq 'ARRAY' ) {
            return $self->send_comet_response( [ @comet_stack, map { Cpanel::JSON::Load($_) } @$comet_feeds ] );
        }
        else {
            return $self->send_comet_response(
                [
                    {
                        ( $COMET_DEBUG ? ( 'pid' => $$ ) : () ),
                        'successful' => 'false',
                        'error'      => 'internal server error',
                        'clientId'   => $self->{'cometd'}->{'clientId'},
                    }
                ]
            );
        }
    }
    return $self->send_comet_response( \@comet_stack );
}

sub send_comet_response {
    my ( $self, $response_ref, $http_status ) = @_;
    my $server_obj = $self->get_server_obj();

    $http_status ||= 200;
    my $response = Cpanel::JSON::Dump($response_ref);
    syswrite( STDERR, "$$: [comet_response] = $response\n" ) if $COMET_DEBUG;
    $server_obj->response()->set_state_sent_headers_to_socket();
    $server_obj->write_buffer( $server_obj->fetchheaders( $Cpanel::Server::Constants::FETCHHEADERS_STATIC_CONTENT, $http_status ) . 'Content-type: ' . $Cpanel::Server::JSON_MIME_TYPE . "\r\nContent-Length: " . length($response) . "\r\n\r\n" . $response );
    $server_obj->check_pipehandler_globals();
    return 1;
}

1;
