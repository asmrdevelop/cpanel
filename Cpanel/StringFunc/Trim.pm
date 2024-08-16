package Cpanel::StringFunc::Trim;

# cpanel - Cpanel/StringFunc/Trim.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

$Cpanel::StringFunc::Trim::VERSION = '1.02';

my %ws_chars = ( "\r" => undef, "\n" => undef, " " => undef, "\t" => undef, "\f" => undef );

sub trim {
    my ( $str, $totrim ) = @_;
    $str = rtrim( ltrim( $str, $totrim ), $totrim );
    return $str;
}

sub ltrim {
    my ( $str, $totrim ) = @_;
    $str =~ s/^$totrim*//;
    return $str;
}

sub rtrim {
    my ( $str, $totrim ) = @_;
    $str =~ s/$totrim*$//;
    return $str;
}

sub endtrim {
    my ( $str, $totrim ) = @_;

    if ( substr( $str, ( length($totrim) * -1 ), length($totrim) ) eq $totrim ) {
        return substr( $str, 0, ( length($str) - length($totrim) ) );
    }
    return $str;
}

sub begintrim {
    my ( $str, $totrim ) = @_;

    if (
        defined $str && defined $totrim    # .
        && substr( $str, 0, length($totrim) ) eq $totrim
    ) {
        return substr( $str, length($totrim) );
    }
    return $str;
}

sub ws_trim {
    my ($this) = @_;

    return unless defined $this;

    my $fix = ref $this eq 'SCALAR' ? $this : \$this;

    return unless defined $$fix;

    if ( $$fix =~ tr{\r\n \t\f}{} ) {
        ${$fix} =~ s/^\s+// if exists $ws_chars{ substr( $$fix, 0,  1 ) };
        ${$fix} =~ s/\s+$// if exists $ws_chars{ substr( $$fix, -1, 1 ) };
    }
    return ${$fix};
}

sub ws_trim_array {
    my $ar = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];    # [@_] :: copy @_ w/ out unpack first: !! not \@_ in this case !!
    foreach my $idx ( 0 .. scalar( @{$ar} ) - 1 ) {
        $ar->[$idx] = ws_trim( $ar->[$idx] );
    }
    return wantarray ? @{$ar} : $ar;
}

sub ws_trim_hash_values {
    my $hr = ref $_[0] eq 'HASH' ? $_[0] : {@_};     # {@_} :: copy @_ w/ out unpack first:
    foreach my $key ( keys %{$hr} ) {
        $hr->{$key} = ws_trim( $hr->{$key} );
    }
    return wantarray ? %{$hr} : $hr;
}

1;

__END__

=head1 Functions

These functions trim strings.

=head2 endtrim($string, $trim)

Returns a string that is $string with $trim removed from the end (once not globally)

=head2 beingtrim($string, $trim)

Returns a string that is $string with $trim removed from the beginning (once not globally)

=head2 ws_trim()

Given a string or scalar reference, returns the string with leading and trailing whitespace trimmed.

If a reference is passed it is also updated.

=head2 ws_trim_array()

Given an array or arrayreference, returns the array (or array ref in scalar context) with leading and trailing whitespace trimmed.

If a reference is passed it is also updated.

=head2 ws_trim_hash_values()

Given a hash or hash reference, returns the hash (or hash ref in scalar context) with each key's value having leading and trailing whitespace trimmed.

If a reference is passed it is also updated.
