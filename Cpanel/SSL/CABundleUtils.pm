package Cpanel::SSL::CABundleUtils;

# cpanel - Cpanel/SSL/CABundleUtils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception              ();
use Cpanel::LoadModule             ();
use Cpanel::OrDie                  ();
use Cpanel::SSL::Objects::CABundle ();
use Cpanel::SSL::Utils             ();
use Cpanel::SSL::Verify            ();

our $CABUNDLE_SERVER = 'https://cabundle.cpanel.net';

#Returns undef if none of the CABs is valid; otherwise, gives the best one back.
#
sub pick_best_cabundle {
    my (@cabs) = @_;

    die "Need at least two CABs!" if grep { !length } @cabs[ 0, 1 ];

    my @cab_objs = map { Cpanel::SSL::Objects::CABundle->new( cab => $_ ) } @cabs;

    @cab_objs = grep { _verify_cab_object($_) } @cab_objs;

    return undef if !@cab_objs;

    if ( @cab_objs > 1 ) {

        #Hm, ok. We have >1 verified CAB. Then we need to prioritize:
        #   - latest expiration time
        #   - longest modulus length
        #   - latest start time
        #
        my @higher_is_better_comparisons = qw(
          get_earliest_not_after
          get_encryption_strength
          get_not_before
        );

        for my $func (@higher_is_better_comparisons) {
            my @numbers = map { $_->$func() } @cab_objs;
            my $highest = ( sort { $b <=> $a } @numbers )[0];
            @cab_objs = grep { $_->$func() == $highest } @cab_objs;

            last if @cab_objs < 2;
        }

        if ( @cab_objs > 1 ) {

            #Wow, multiple verified cabs with the same expiration, start time, and encryption strength?
            #Ok, then take the longest. Yes, the LONGEST because a longer CA bundle probably has
            #an extra root certificate that some old SSL clients may need in order to verify the
            #certificate.
            #
            my @texts          = map { _normalize_order_or_die($_) } @cab_objs;
            my $longest_length = length( ( sort { length($b) <=> length($a) } @texts )[0] );
            @cab_objs = grep { length( _normalize_order_or_die($_) ) == $longest_length } @cab_objs;
        }
    }

    return $cab_objs[0] && _normalize_order_or_die( $cab_objs[0] );
}

sub fetch_cabundle_from_cpanel_repo {
    my ($c_pem) = @_;

    # Cpanel::HttpRequest won't handle port 443 properly.
    Cpanel::LoadModule::load_perl_module('Cpanel::HTTP::Client');

    my $client   = Cpanel::HTTP::Client->new;
    my $response = $client->post_form( "$CABUNDLE_SERVER/v1.0/get_certificate_bundle", { 'certificate' => $c_pem } );
    my $json     = $response->{'content'};

    if ( !$json ) {
        die Cpanel::Exception->create_raw("Failed to fetch cabundle information from cabundle.cpanel.net: invalid response");
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
    return Cpanel::JSON::Load($json);
}

#----------------------------------------------------------------------

sub _normalize_order_or_die {
    my ($cab_obj) = @_;

    return Cpanel::OrDie::multi_return(
        sub {
            $cab_obj->normalize_order_without_trusted_root_certs();
        }
    );
}

sub _validate_cab_form {
    my ($cab) = @_;

    return ( Cpanel::SSL::Utils::find_leaf_in_cabundle($cab) )[0];
}

#overridden in tests
sub _verify_cab_object {
    my ($cab) = @_;

    my $text = _normalize_order_or_die($cab);

    return Cpanel::SSL::Verify->new()->verify($text)->ok();
}

1;
