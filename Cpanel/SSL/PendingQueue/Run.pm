package Cpanel::SSL::PendingQueue::Run;

# cpanel - Cpanel/SSL/PendingQueue/Run.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Locale                               ();
use Cpanel::AdminBin::Call                       ();
use Cpanel::API                                  ();
use Cpanel::Context                              ();
use Cpanel::Exception                            ();
use Cpanel::Market                               ();
use Cpanel::Market::Provider::cPStore::Constants ();
use Cpanel::Security::Authz                      ();
use Cpanel::SSL::PendingQueue                    ();
use Cpanel::WebVhosts                            ();
use Cpanel::PwCache                              ();
use Cpanel::Domain::Authz                        ();

use constant THROTTLE_VALUES => qw( default none );

#exposed for testing
our $_DELETE_ENTRY_AFTER = 30 * 86400;    #thirty days

sub _send_err_to_user {
    my ($message) = @_;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'notify_call',
        'SEND_ERROR',
        'SSLPendingQueue',
        "$0 encountered an error: $message",
    );

    return;
}

sub process (%args) {
    my $poll_all_yn;

    if ( my $throttle = $args{'throttle'} ) {
        if ( !grep { $throttle eq $_ } THROTTLE_VALUES ) {
            die "Invalid throttle: $throttle";
        }

        $poll_all_yn = $throttle eq 'none';
    }

    Cpanel::Context::must_not_be_scalar();
    Cpanel::Security::Authz::verify_not_root();

    my $cpanel_user = ( Cpanel::PwCache::getpwuid_noshadow($>) )[0];

    my @return;

    try {
        my $still_need_to_poll = 0;
        my $modified           = 0;

        my $poll_db = Cpanel::SSL::PendingQueue->new();

      QUEUE_ITEM:
        for my $item ( $poll_db->read() ) {
            if ( !$poll_all_yn && !$item->is_ready_to_poll() ) {
                $still_need_to_poll = 1;
                next QUEUE_ITEM;
            }

            $modified = 1;
            $item->update_poll_times();

            my $order_item_id   = $item->order_item_id();
            my $provider_module = Cpanel::Market::get_and_load_module_for_provider( $item->provider() );

            my $cert_hr = $provider_module->can('get_certificate_if_available')->($order_item_id);

            if ( my $encrypted_action_urls = $cert_hr->{'encrypted_action_urls'} ) {
                my $previous_action_urls = $item->last_action_urls();
                my $action_urls          = _decrypt_and_save_action_urls( $encrypted_action_urls, $item, $provider_module );
                _notify_if_action_urls_have_changed( $previous_action_urls, $action_urls, $item );
            }

            $item->last_status_code( $cert_hr->{'status_code'} );
            $item->last_status_message( $cert_hr->{'status_message'} );

            my %ret_item = (
                %{ $item->to_hashref() },
                domains   => [ $item->domains() ],
                deleted   => 0,
                expired   => 0,
                installed => 0,
                ( map { $_ => $cert_hr->{$_} } qw(certificate_pem) ),
            );
            push @return, \%ret_item;

            # We need to make sure the user still owns this domain before trying to process it.
            # Ownership or existence could have changed between poll times.
            try {
                Cpanel::Domain::Authz::validate_user_control_of_domains__allow_wildcard( $cpanel_user, \@{ $ret_item{domains} } )
            }
            catch {
                _send_err_to_user($_);
                $poll_db->remove_item($item);
                $ret_item{'deleted'} = 1;
            } and next QUEUE_ITEM;

            my $keep_item;

            if ( $cert_hr->{'certificate_pem'} ) {
                _install_cert(
                    $item,
                    $cert_hr->{'certificate_pem'},
                    [ $item->vhost_names() ],
                );
                $ret_item{'installed'} = 1;
            }
            else {
                my $deleted_in_store_yn = grep { $_ eq ( $cert_hr->{'status_code'} || q<> ) } Cpanel::Market::Provider::cPStore::Constants::FINAL_CPSTORE_CERTIFICATE_ERRORS();
                $ret_item{'expired'} = ( $item->created_time() + $_DELETE_ENTRY_AFTER < time ) ? 1 : 0;

                $keep_item = !$deleted_in_store_yn;
                $keep_item &&= !$ret_item{'expired'};

                $poll_db->update_item($item) if $keep_item;
            }

            if ($keep_item) {
                $still_need_to_poll++;
            }
            else {
                $poll_db->remove_item($item);
                $ret_item{'deleted'} = 1;
            }
        }

        if ( !$still_need_to_poll ) {
            Cpanel::AdminBin::Call::call(
                'Cpanel',
                'ssl_call',
                'STOP_POLLING',
            );
        }

        _close_or_finish_if_modified( $poll_db, $modified );
    }
    catch {
        _send_err_to_user( Cpanel::Exception::get_string($_) );
        local $@ = $_;
        die;
    };

    return @return;
}

#----------------------------------------------------------------------

sub _install_cert {
    my ( $item_obj, $cert, $vhost_names_ar ) = @_;

    #So we can make API calls.
    #(Or should this play behind the API layer?)
    require Cpanel;
    Cpanel::initcp();

    #NOTE: In cases where there are multiple vhosts, this will blow up
    #on the first failed install. Subsequent attempts to install will re-fetch
    #the certificate. We could optimize this at some point if it makes much
    #difference. Note that, currently, installing a single cert onto multiple
    #vhosts by this mechanism isn’t well-tested.

    for my $vhname (@$vhost_names_ar) {
        my $domain = Cpanel::WebVhosts::get_a_domain_on_vhost($vhname);
        my $api    = Cpanel::API::execute(
            'SSL',
            'install_ssl',
            {
                domain => $domain,
                cert   => $cert,
            },
        );

        if ( !$api->status() ) {
            my $msg = join( ' ', @{ $api->errors() || [] }, @{ $api->messages() || [] } );

            my $locale = Cpanel::Locale->new();
            die $locale->maketext( 'The system retrieved the [output,abbr,SSL,Secure Sockets Layer] certificate for “[_1]”, but failed to install it because of an error: [_2]. The system will attempt to fetch the certificate and to install it again.', $vhname, $msg );
        }

        Cpanel::AdminBin::Call::call(
            'Cpanel',
            'notify_call',
            'NOTIFY_SSL_QUEUE_INSTALL',
            certificate_pem => $cert,
            vhost_name      => $vhname,
            (
                map { $_ => $item_obj->$_() }
                  qw(
                  product_id
                  order_id
                  order_item_id
                  provider
                  )
            ),
        );
    }

    return;
}

# tested directly
sub _decrypt_and_save_action_urls {
    my ( $encrypted_action_urls, $item, $provider_module ) = @_;

    my (@key_with_text) = $provider_module->can('get_key_with_text_for_csr')->( $item->csr_parse() );
    my $action_urls = $provider_module->can('decrypt_action_urls')->( @key_with_text, $encrypted_action_urls );
    $item->last_action_urls($action_urls);

    return $action_urls;
}

sub _notify_if_action_urls_have_changed {
    my ( $previous_action_urls, $action_urls, $item ) = @_;

    require Cpanel::JSON;

    # If there were not action urls or the urls change
    # we send a new action required email
    if (
        !$previous_action_urls ||    #
        ( $action_urls && Cpanel::JSON::canonical_dump($previous_action_urls) ne Cpanel::JSON::canonical_dump($action_urls) )
    ) {
        return _send_action_needed_notification($item);
    }
    return;
}

sub _send_action_needed_notification {
    my ($item) = @_;
    my $hr = $item->to_hashref();
    return Cpanel::AdminBin::Call::call(
        'Cpanel',
        'notify_call',
        'NOTIFY_SSL_QUEUE_CERT_ACTION_NEEDED',
        ( map { $_ => $hr->{$_} } qw(username vhost_name product_id order_id order_item_id provider csr) ),
        ( 'action_urls' => $item->last_action_urls() )
    );
}

sub _close_or_finish_if_modified {
    my ( $poll_db, $modified ) = @_;

    # finish will re-write the db and release the lock
    # close will not update the db and release the lock
    return $modified ? $poll_db->finish() : $poll_db->close();
}

1;
