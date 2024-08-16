package Cpanel::Version::Compare;

# cpanel - Cpanel/Version/Compare.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=head1 NAME

Cpanel::Version::Compares - Compare 2 version strings with up to 4 numeric sequences each

=head1 USAGE

    use Cpanel::Version::Compare ();
    Cpanel::Version::Compare::compare(...)

=head1 DESCRIPTION

used primarily to compare 2 cPanel versions

=head1 SUBROUTINES

=over

=item B<compare>

returns a boolean if comparison is true or not:

   Cpanel::Versions::compare($versa, '>=', $versb);

comparison mode can be <, >, ==, !=, <=, >=

=cut

# used by sub compare

my %modes = (
    '>' => sub ( $check, $against ) {
        return if $check eq $against;    # no need to continue if they are the same

        return ( cmp_versions( $check, $against ) > 0 );
    },
    '<' => sub ( $check, $against ) {
        return if $check eq $against;    # no need to continue if they are the same

        return ( cmp_versions( $check, $against ) < 0 );
    },
    '==' => sub ( $check, $against ) {
        return ( $check eq $against || cmp_versions( $check, $against ) == 0 );
    },
    '!=' => sub ( $check, $against ) {
        return ( $check ne $against && cmp_versions( $check, $against ) != 0 );
    },
    '>=' => sub ( $check, $against ) {
        return 1 if $check eq $against;    # no need to continue if they are the same
        return ( cmp_versions( $check, $against ) >= 0 );
    },
    '<=' => sub ( $check, $against ) {
        return 1 if $check eq $against;    # no need to continue if they are the same
        return ( cmp_versions( $check, $against ) <= 0 );
    },
    '<=>' => sub ( $check, $against ) {
        return cmp_versions( $check, $against );
    },
);

sub compare ( $check, $mode, $against ) {
    ## fix it for them ?
    # chomp($check);
    # chomp($against);
    ## remove beginning or ending dots ?
    # $check   =~ s{(?:^[.]|[.]$)}{}g;
    # $against =~ s{(?:^[.]|[.]$)}{}g;

    if ( !defined $mode || !exists $modes{$mode} ) {

        # warn/log - invalid mode
        return;
    }
    foreach my $ver ( $check, $against ) {

        # Now supports old style versions and new style
        # Old: 11.28.87-STABLE_51188
        # New: 11.23.4.5
        # if ( $ver !~ m{ \A \d+(?:\.\d+)* \z }xms ) {
        $ver //= '';
        if ( $ver !~ m{ ^((?:\d+[._]){0,}\d+[a-z]?).*?$ }axms ) {

            # warn/log - invalid version
            return;
        }

        $ver = $1;
    }

    $check   =~ s/_/\./g;
    $against =~ s/_/\./g;

    # Convert 0.9.7a to 0.9.7.97
    $check   =~ s/([a-z])$/'.' . ord($1)/e;
    $against =~ s/([a-z])$/'.' . ord($1)/e;

    # make sure we have 2: 3 decimal version numbers
    my @check_len   = split( /[_\.]/, $check );
    my @against_len = split( /[_\.]/, $against );

    if ( @check_len > 4 ) {

        # warn/log - invalid version
        return;
    }
    elsif ( @check_len < 4 ) {
        for ( 1 .. 4 - @check_len ) {
            $check .= '.0';
        }
    }

    if ( @against_len > 4 ) {

        # warn/log - invalid version
        return;
    }
    elsif ( @against_len < 4 ) {
        for ( 1 .. 4 - @against_len ) {
            $against .= '.0';
        }
    }

    # Final safety. This code might be unreachable?
    return if $check   !~ m { \A \d+\.\d+\.\d+\.\d+ \z }axms;
    return if $against !~ m { \A \d+\.\d+\.\d+\.\d+ \z }axms;

    return $modes{$mode}->( $check, $against );
}

=item B<cmp_versions>

Only designed to do a simple comparison of 2 versions with 3 dots or underscores in them. does a <==> comparson for each number

    cmp_versions("11.1.2.3", "11.2.2.3") would return -1

=cut

sub cmp_versions ( $left, $right ) {
    my ( $maj, $min, $rev, $sup ) = split /[\._]/, $left;
    my ( $mj,  $mn,  $rv,  $sp )  = split /[\._]/, $right;

    return $maj <=> $mj || $min <=> $mn || $rev <=> $rv || $sup <=> $sp;
}

=item B<get_major_release>

When passed a version number, it strips off the first to and returns the rounded up (to even) version number

    Example:
    get_major_release("11.21.x.x"); # returns 11.22;
    get_major_release("11.70.5.5"); # returns 11.70;

=cut

sub get_major_release ( $version = '' ) {
    $version =~ s/\s*//g;
    my ( $major, $minor );
    if ( $version =~ m/^([0-9]+)\.([0-9]+)/ ) {
        $major = int $1;
        $minor = int $2;
    }
    else {
        return;
    }
    $minor++ if $minor % 2;
    return "$major.$minor";
}

=item B<compare_major_release>

strips off the top 2 version numbers and does a comparison on them

    Example:
    compare_major_release("11.70.0.0", "==", "11.69.22.2); # This would be true since both major versions are 11.70

=cut

sub compare_major_release ( $check, $mode, $against ) {

    return unless defined $check && defined $mode && defined $against;
    my $maj1 = get_major_release($check);
    return unless defined $maj1;
    my $maj2 = get_major_release($against);
    return unless defined $maj2;
    return $modes{$mode}->( $maj1, $maj2 );
}

=back

=cut

1;
