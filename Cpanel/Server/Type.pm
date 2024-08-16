package Cpanel::Server::Type;

# cpanel - Cpanel/Server/Type.pm                      Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

use constant NUMBER_OF_USERS_TO_ASSUME_IF_UNREADABLE => 1;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type - Helpers to check which cPanel product is valid

=head1 SYNOPSIS

    use Cpanel::Server::Type ();

    my $max_users  = Cpanel::Server::Type::get_max_users();
    my $is_dnsonly = Cpanel::Server::Type::is_dnsonly();

=head1 DESCRIPTION

This module is used to read information from the license file.
Getting this information from the license file is generally considered safe since any changes to the file will cause the whole cPanel system to stop working.

=cut

sub _get_license_file_path { return q{/usr/local/cpanel/cpanel.lisc} }
sub _get_dnsonly_file_path { return q{/var/cpanel/dnsonly} }

use constant _ENOENT => 2;

#
# The SERVER_TYPE constant describes the flavor of the build
#   and what product it's designed for.
# It's driving the special symkink file /usr/local/cpanel/server.type
#
use constant SERVER_TYPE => q[cpanel];

my @server_config;
our %PRODUCTS;
our $MAXUSERS;
our %FIELDS;
our ( $DNSONLY_MODE, $NODE_MODE );

=head1 FUNCTIONS

=head2 is_dnsonly

This function determines if the license is a dnsonly license. Note that this is no longer determined based on /var/cpanel/dnsonly.
Returns based on the 'products' entry in the license file. If the file is missing, then it returns 1 (defaults to dnsonly).

=cut

sub is_dnsonly {
    return $DNSONLY_MODE if defined $DNSONLY_MODE;

    return 1 if -e _get_dnsonly_file_path();
    return 0 if $! == _ENOENT();
    my $err = $!;

    # An error other than ENOENT means we can’t determine whether the
    # DNSONLY flag file exists, which means we can’t fulfill the caller’s
    # request; thus, an exception is reasonable.

    if ( _read_license() ) {
        return $PRODUCTS{'dnsonly'} ? 1 : 0;
    }

    die sprintf( 'stat(%s): %s', _get_dnsonly_file_path(), "$err" );
}

=head2 is_wp_squared

Returns a boolean to check if the server is a WP Squared install.

=cut

sub is_wp_squared {
    return SERVER_TYPE eq 'wp2';
}

=head2 get_producttype

This function returns a string describing what kind of cPanel system is being provided.

Returns an uppercase string describing the licensed capabilities of the cPanel system.
If the license file cannot be read, DNSONLY will be assumed. Possible return values:

=over

=item STANDARD

=item DNSONLY

=item DNSNODE

=item MAILNODE

=item DATABASENODE

=back

=cut

sub get_producttype {
    return $NODE_MODE if defined $NODE_MODE;
    return 'DNSONLY' unless _read_license();

    return 'STANDARD' if $PRODUCTS{'cpanel'};

    foreach my $product (qw/dnsnode mailnode databasenode dnsonly/) {
        return uc($product) if $PRODUCTS{$product};
    }

    return 'DNSONLY';
}

=head2 get_max_users

This function gets the value of the 'maxusers' entry in the license file. If the license file cannot be read, then it will be treated like a single user license.

=cut

sub get_max_users {
    return $MAXUSERS if defined $MAXUSERS;
    return NUMBER_OF_USERS_TO_ASSUME_IF_UNREADABLE unless _read_license();
    return $MAXUSERS // NUMBER_OF_USERS_TO_ASSUME_IF_UNREADABLE;
}

sub get_license_expire_gmt_date {
    return $FIELDS{'license_expire_gmt_date'} if defined $FIELDS{'license_expire_gmt_date'};
    return 0 unless _read_license();
    return $FIELDS{'license_expire_gmt_date'} // 0;
}

=head2 is_licensed_for_product

This function accepts the name of a product which the cPanel licensing system
can provide and returns true if there is an active and valid license for that
product according to the cPanel license file on this system, or false otherwise.  If no license
file is available, always returns false.

=cut

# assumes that the values of %PRODUCTS don't matter
sub is_licensed_for_product ($product) {
    return unless $product;
    $product = lc $product;
    return unless _read_license();
    return exists $PRODUCTS{$product};
}

=head2 get_features

Returns a list of features attached to this license.

This will be in the form of an array.

=cut

sub get_features {
    return unless _read_license();

    my @features = split( ",", $FIELDS{'features'} // '' );
    return @features;
}

=head2 has_feature

Returns a boolean indicating if the passed feature string is attached to this license.

=cut

sub has_feature ( $feature = undef ) {
    length $feature or return;

    return ( grep { $_ eq $feature } get_features() ) ? 1 : 0;
}

=head2 get_products

This function returns the entire list of products (including third-party products) for which this IP has active and valid licenses
in the cPanel license system, or the number of entries in scalar context. If no license file is available, the list is empty.

=cut

# assumes that the values of %PRODUCTS doesn't matter
sub get_products {
    return unless _read_license();
    return keys %PRODUCTS;
}

sub _read_license {
    my $LICENSE_FILE = _get_license_file_path();

    # Did we already read this successfully?
    my @new_stat = stat($LICENSE_FILE) if @server_config;

    # Size and mtime.
    if ( @server_config && @new_stat && $new_stat[9] == $server_config[9] && $new_stat[7] == $server_config[7] ) {
        return 1;
    }

    open( my $fh, '<', $LICENSE_FILE ) or do {

        # If the file just disappeared then we don’t care, but if the
        # failure is for some other reason then that’s worth a warning.
        if ( $! != _ENOENT() ) {
            warn "open($LICENSE_FILE): $!";
        }

        return;
    };

    # clear the cache.
    _reset_cache();

    my $content;

    # read less content to speedup the parsing (we do not need all data)
    read( $fh, $content, 1024 ) // do {
        warn "read($LICENSE_FILE): $!";
        $content = q<>;
    };

    return _parse_license_contents_sr( $fh, \$content );
}

sub _parse_license_contents_to_hashref ($content_sr) {

    # Please leave this as pure Perl rather than pulling in, e.g.,
    # Colon::Config. Given that we cache this parse, it’s better
    # to optimize for memory usage rather than for speed.
    #
    my %vals = map { ( split( m{: }, $_ ) )[ 0, 1 ] } split( m{\n}, $$content_sr );

    return \%vals;
}

sub _parse_license_contents_sr ( $fh, $content_sr ) {
    my $vals_hr = _parse_license_contents_to_hashref($content_sr);

    if ( length $vals_hr->{'products'} ) {
        %PRODUCTS = map { ( $_ => 1 ) } split( ",", $vals_hr->{'products'} );
    }
    else {
        return;
    }

    if ( length $vals_hr->{'maxusers'} ) {

        # Compiled code will have already initialized this value
        # and made it read-only.  We only need to set this value once.
        $MAXUSERS //= int $vals_hr->{'maxusers'};
    }
    else {
        return;
    }

    foreach my $field (qw/license_expire_time license_expire_gmt_date support_expire_time updates_expire_time/) {
        $FIELDS{$field} = $vals_hr->{$field} // 0;
    }
    foreach my $field (qw/client features/) {
        $FIELDS{$field} = $vals_hr->{$field} // '';
    }

    if ( length $vals_hr->{'fields'} ) {
        foreach my $field ( split( ",", $vals_hr->{'fields'} ) ) {
            my ( $k, $v ) = split( '=', $field, 2 );
            $FIELDS{$k} = $v;

        }
    }
    else {
        return;
    }

    # Cache when we last read it
    @server_config = stat($fh);
    return 1;
}

sub _reset_cache {
    undef %PRODUCTS;
    undef %FIELDS;
    undef @server_config;
    undef $MAXUSERS;
    undef $DNSONLY_MODE;

    return;
}

1;

__END__

=pod

=head1 CONFIGURATION AND ENVIRONMENT

This module requires a cPanel&WHM environment server.

=head1 DEPENDENCIES

none

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

No known issues at this time.
