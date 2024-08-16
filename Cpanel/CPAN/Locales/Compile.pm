package Cpanel::CPAN::Locales::Compile;

use strict;
use warnings;

sub plural_rule_string_to_code {
    my ( $plural_rule_string, $return ) = @_;
    if ( !defined $return ) {
        $return = 1;
    }

    # if you have a better way, patches welcome!!

    my %m;
    while ( $plural_rule_string =~ m/mod ([0-9]+)/g ) {

        # CLDR plural rules (http://unicode.org/reports/tr35/#Language_Plural_Rules):
        #      'mod' (modulus) is a remainder operation as defined in Java; for example, the result of "4.3 mod 3" is 1.3.
        $m{$1} = "( (\$_[0] % $1) + (\$_[0]-int(\$_[0])) )";
    }

    my $perl_code = "sub { if (";

    for my $or ( split /\s+or\s+/i, $plural_rule_string ) {
        my $and_exp;
        for my $and ( split /\s+and\s+/i, $or ) {
            my $copy = $and;
            my $n    = '$_[0]';

            $copy =~ s/ ?n is not / $n \!\= /g;
            $copy =~ s/ ?n is / $n \=\= /g;

            $copy =~ s/ ?n mod ([0-9]+) is not / $m{$1} \!\= /g;
            $copy =~ s/ ?n mod ([0-9]+) is / $m{$1} \=\= /g;

            # 'in' is like 'within' but it has to be an integer
            $copy =~ s/ ?n not in ([0-9]+)\s*\.\.\s*([0-9]+) ?/ int\($n\) \!\= $n \|\| $n < $1 \|\| $n \> $2 /g;
            $copy =~ s/ ?n mod ([0-9]+) not in ([0-9]+)\s*\.\.\s*([0-9]+) ?/ int\($n\) \!\= $n \|\| $m{$1} < $2 \|\| $m{$1} \> $3 /g;

            # 'within' is like 'in' except is inclusive of decimals
            $copy =~ s/ ?n not within ([0-9]+)\s*\.\.\s*([0-9]+) ?/ \($n < $1 \|\| $n > $2\) /g;
            $copy =~ s/ ?n mod ([0-9]+) not within ([0-9]+)\s*\.\.\s*([0-9]+) ?/ \($m{$1} < $2 \|\| $m{$1} > $3\) /g;

            # 'in' is like 'within' but it has to be an integer
            $copy =~ s/ ?n in ([0-9]+)\s*\.\.\s*([0-9]+) ?/ int\($n\) \=\= $n \&\& $n \>\= $1 \&\& $n \<\= $2 /g;
            $copy =~ s/ ?n mod ([0-9]+) in ([0-9]+)\s*\.\.\s*([0-9]+) ?/ int\($n\) \=\= $n \&\& $m{$1} \>\= $2 \&\& $m{$1} \<\= $3 /g;

            # 'within' is like 'in' except is inclusive of decimals
            $copy =~ s/ ?n within ([0-9]+)\s*\.\.\s*([0-9]+) ?/ $n \>\= $1 \&\& $n \<\= $2 /g;
            $copy =~ s/ ?n mod ([0-9]+) within ([0-9]+)\s*\.\.\s*([0-9]+) ?/ $m{$1} \>\= $2 \&\& $m{$1} \<\= $3 /g;

            if ( $copy eq $and ) {
                require Carp;
                Carp::carp("Unknown plural rule syntax");
                return;
            }
            else {
                $and_exp .= "($copy) && ";
            }
        }
        $and_exp =~ s/\s+\&\&\s*$//;

        if ($and_exp) {
            $perl_code .= " ($and_exp) || ";
        }
    }
    $perl_code =~ s/\s+\|\|\s*$//;

    $perl_code .= ") { return '$return'; } return;}";

    return $perl_code;
}

sub plural_rule_string_to_javascript_code {
    my ( $plural_rule_string, $return ) = @_;
    my $perl = plural_rule_string_to_code( $plural_rule_string, $return );
    $perl =~ s/sub \{ /function (n) \{/;
    $perl =~ s/\$_\[0\]/n/g;
    $perl =~ s/ \(n \% ([0-9]+)\) \+ \(n-int\(n\)\) /n % $1/g;
    $perl =~ s/int\(/parseInt\(/g;
    return $perl;
}

1;
