package Cpanel::FileFormat::Ini;

# cpanel - Cpanel/FileFormat/Ini.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#

sub _strip {
    my ($s) = @_;

    $s =~ s/^\s+//;
    $s =~ s/\s+$//;

    return $s;
}

sub _unquote {
    my ($s) = @_;

    if ( $s =~ /^'([^']+)'$/ || $s =~ /^"([^"]+)"$/ ) {
        $s = $1;
    }

    return $s;
}

sub read_file {
    my ( $class, $file ) = @_;
    my ( $section, $key, $ret ) = ( undef, undef, {} );

    open( my $fh, '<', $file ) or die("Unable to open configuration file $file for reading");

    while ( my $buf = readline($fh) ) {
        next unless my $line = _strip($buf);
        next if $line =~ /^#/;

        if ( $line =~ /^([^=]+)=(.*)$/ ) {

            # Key-value assignments
            $section                 = 'default' unless defined $section;
            $key                     = _strip($1);
            $ret->{$section}->{$key} = _unquote( _strip($2) );
        }
        elsif ( $line =~ /^\[([^\[\]]+)\]$/i ) {

            # Section headers
            $section = _strip($1);
            $ret->{$section} ||= {};
        }
        else {

            # Line continuations
            die("Syntax error: $line") unless defined $ret->{$section}->{$key};
            $ret->{$section}->{$key} .= ' ' . _strip($line);
        }
    }

    close($fh);

    return bless $ret, $class;
}

1;
