package Cpanel::Ftp::Passwd;

# cpanel - Cpanel/Ftp/Passwd.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class parses and represents an FTP passwd file.
#
# Instantiate with one of two arguments:
#   - scalar ref (parsed as a passwd file)
#   - array ref - each item is either:
#       Cpanel::Ftp::PasswdEntry object, or
#       interpreted as a Cpanel::Ftp::PasswdEntry constructor arg
#
# This class's constructor will die() on errors, so always wrap in eval {}.
#
# Array ref may not be the most efficient model for this...?
#----------------------------------------------------------------------

use strict;

use Cpanel::Ftp::PasswdEntry ();

my $PACKAGE = __PACKAGE__;

my %parser = (
    SCALAR => '_parse_passwd_file',
    ARRAY  => '_parse_array',
);

sub _parse_array {
    my ( $self, $contents_ar ) = @_;

    for my $item (@$contents_ar) {
        if (
            do {
                local $@;
                eval { $item->isa('Cpanel::Ftp::PasswdEntry') };
            }
        ) {
            push @$self, $item;
        }
        else {
            push @$self, Cpanel::Ftp::PasswdEntry->new($item);
        }
    }

    return;
}

sub _parse_passwd_file {
    my ( $self, $contents_sr ) = @_;

    while ( $$contents_sr =~ m{[^\n]+\n?}g ) {
        my $line = substr( $$contents_sr, $-[0], $+[0] - $-[0] );

        $line =~ s{#.*}{};
        $line =~ s{\A\s+|\s+\z}{}g;
        next if !length($line);

        push @$self, Cpanel::Ftp::PasswdEntry->new( \$line );
    }

    return;
}

#NOTE: This can die().
sub new {
    my ( $class, $contents_ref ) = @_;

    my $self = bless [], $class;

    my $parser_name = $parser{ ref $contents_ref };

    die( "Invalid argument to $PACKAGE: " . ref $contents_ref ) if !$parser_name;

    $self->$parser_name($contents_ref);

    return $self;
}

sub to_string {
    my ($self) = @_;

    return join q{}, map { $_->to_string() . "\n" } @$self;
}

sub get_entries {
    my ($self) = @_;

    return [@$self];
}

1;
