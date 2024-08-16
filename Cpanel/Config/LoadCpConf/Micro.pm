package Cpanel::Config::LoadCpConf::Micro;

# cpanel - Cpanel/Config/LoadCpConf/Micro.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

my %conf;

sub loadcpconf {
    tie %conf, 'Cpanel::Config::LoadCpConf::Micro::Tie' if !tied(%conf);
    return \%conf;
}

package Cpanel::Config::LoadCpConf::Micro::Tie;

sub FETCH {
    my $s   = shift;
    my $key = shift;

    _load( $s, $key );

    return exists $s->{$key} ? $s->{$key}->{'value'} : undef;
}

sub _load {
    my ( $s, $key ) = @_;
    my $cpconf_mtime = ( stat('/var/cpanel/cpanel.config') )[9];
    if ( !exists $s->{$key} || $s->{$key}->{'mtime'} != $cpconf_mtime ) {
        die "Invalid key: “$key”" if $key =~ tr{A-Za-z0-9._-}{}c;
        $s->{$key}->{'mtime'} = $cpconf_mtime;
        $s->{$key}->{'value'} = `/usr/local/cpanel/bin/fetch_cpconf_value $key`;
        $s->{$key}->{'value'} = undef if $? >> 8 == 2;                             #exit code of 2 means undef or it did not exist
    }
    return 1;
}

sub STORE {

}

sub TIEHASH {
    my $c = shift;
    my $s = {};

    bless $s, $c;

    return $s;
}

sub EXISTS {
    my $s   = shift;
    my $key = shift;

    if ( exists $s->{$key} ) {
        return exists $s->{$key};
    }
    _load( $s, $key );

    return exists $s->{$key};
}

sub FIRSTKEY {
    my $a = keys %{ $_[0] };    # reset each() iterator
    return scalar each %{ $_[0] };
}

sub NEXTKEY {
    return scalar each %{ $_[0] };
}

1;
