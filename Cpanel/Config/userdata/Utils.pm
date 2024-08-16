
# cpanel - Cpanel/Config/userdata/Utils.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module includes code for parsing a userdata structure such
# as what Cpanel::Config::userdata::Load::load_userdata_main() returns.
#----------------------------------------------------------------------

package Cpanel::Config::userdata::Utils;

use strict;

use Cpanel::Context ();

our %DOMAIN_KEY_TYPE = qw(
  addon_domains   HASH
  parked_domains  ARRAY
  sub_domains     ARRAY
);

#This returns a list literal and so must be called in list context.
sub get_all_domains_from_main_userdata {
    Cpanel::Context::must_be_list();
    return @{ get_all_domains_from_main_userdata_ar( $_[0] ) };
}

sub get_all_domains_from_main_userdata_ar {
    my ($ud_main) = @_;
    return [
        $ud_main->{'main_domain'},
        ( map { ref $ud_main->{$_} eq 'HASH' ? keys %{ $ud_main->{$_} } : ref $ud_main->{$_} eq 'ARRAY' ? @{ $ud_main->{$_} } : () } keys %DOMAIN_KEY_TYPE )
    ];
}

#NOTE: This will return a single undef if the $ud_vh passed in
#doesn’t have a “servername”. This is kinda by design, as we really
#shouldn’t get here in that case--it probably indicates that the load()
#operation failed somehow (maybe the userdata file didn’t exist?).
sub get_all_vhost_domains_from_vhost_userdata {
    my ($ud_vh) = @_;

    Cpanel::Context::must_be_list();

    #wildcard subdomains have only their “servername”;
    #Doing a return here prevents ( '*.foo.com', '*.foo.com' ).
    return $ud_vh->{'servername'} if 0 == rindex( $ud_vh->{'servername'}, '*', 0 );

    return (
        $ud_vh->{'servername'},
        $ud_vh->{'serveralias'} ? split( m<\s+>, $ud_vh->{'serveralias'} ) : (),
    );
}

#Returns undef if we don’t actually have the domain.
#Accommodates any domain that Apache will recognize for the given
#userdata object.
sub get_vhost_name_for_domain {
    my ( $ud_main, $domain ) = @_;

    #TODO: This will need to accommodate “mail.” subdomains when
    #they get created.

    # The /r regexes were replaced to keep upcp.static happy
    # on c6.
    my @base_domain_opts = ($domain);

    push @base_domain_opts, substr( $domain, 4 ) if rindex( $domain, 'www.', 0 ) == 0;

    if ( $ud_main->{'sub_domains'} ) {
        my $subs = " " . join( " ", @{ $ud_main->{'sub_domains'} } ) . " ";

        for my $dname (@base_domain_opts) {
            return $dname if index( $subs, " $dname " ) > -1;
        }
    }

    for my $sub (qw( mail.  ipv6. )) {
        push @base_domain_opts, substr( $domain, 5 ) if rindex( $domain, $sub, 0 ) == 0;
    }

    for my $dname (@base_domain_opts) {
        if ( $dname eq $ud_main->{'main_domain'} ) {
            return $dname;
        }

        if ( grep { $_ eq $dname } @{ $ud_main->{'parked_domains'} } ) {
            return $ud_main->{'main_domain'};
        }

        if ( $ud_main->{'addon_domains'}{$dname} ) {
            return $ud_main->{'addon_domains'}{$dname};
        }
    }

    #It’ll return undef if it doesn’t exist.
    return $ud_main->{'addon_domains'}{$domain};
}

#For now, all this function does is "rectify" the data structures for
#sub/parked/addon domains.
#NOTE: It accomplishes this by clobbering things that look invalid!
#
#It could be expanded later to cover more of the main userdata structure.
#
sub sanitize_main_userdata {
    my ($userdata) = @_;

    for my $key ( keys %DOMAIN_KEY_TYPE ) {
        if ( ref( $userdata->{$key} ) ne $DOMAIN_KEY_TYPE{$key} ) {
            $userdata->{$key} = $DOMAIN_KEY_TYPE{$key} eq 'HASH' ? {} : [];
        }
    }

    return 1;
}

1;
