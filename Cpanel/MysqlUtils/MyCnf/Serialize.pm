package Cpanel::MysqlUtils::MyCnf::Serialize;

# cpanel - Cpanel/MysqlUtils/MyCnf/Serialize.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %CHARS_TO_ESCAPE = (
    "\x08" => 'b',
    "\x09" => 't',
    "\x0a" => 'n',
    "\x0d" => 'r',
    '\\'   => '\\',

    #These are not documented but are active in
    #MySQL's mysys_ssl/my_default.cc.
    q<"> => q<">,
    q<'> => q<'>,
);

#The input format is a hashref: {
#   section => {
#       key => value    #key=value
#       key => undef    #key
#   },
#}
sub serialize {
    my ($my_cnf_data_hr) = @_;

    my $escape_re_part = join '|', map { quotemeta } keys %CHARS_TO_ESCAPE;

    my @lines;
    for my $section ( sort keys %$my_cnf_data_hr ) {

        my $has_content;
        for my $key ( sort keys %{ $my_cnf_data_hr->{$section} } ) {
            if ( !$has_content ) {
                $has_content = 1;
                push @lines, "[$section]";
            }

            my $val = $my_cnf_data_hr->{$section}{$key};
            if ( defined $val ) {
                $val =~ s<($escape_re_part)><\\$CHARS_TO_ESCAPE{$1}>g;
                push @lines, qq<$key="$val">;
            }
            else {
                push @lines, $key;
            }
        }

        push @lines, q<> if $has_content;
    }

    return join( "\n", @lines ) . "\n";
}

1;
