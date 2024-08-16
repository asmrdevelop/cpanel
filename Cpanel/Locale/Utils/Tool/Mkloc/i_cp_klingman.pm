package Cpanel::Locale::Utils::Tool::Mkloc::i_cp_klingman;

# cpanel - Cpanel/Locale/Utils/Tool/Mkloc/i_cp_klingman.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::CPAN::Locale::Maketext::Utils::Phrase ();

# 0xF8D0..0xF8FF
my @klingon_unicode_range_bytes_list = (
    "\xef\xa3\x90", "\xef\xa3\x91", "\xef\xa3\x92", "\xef\xa3\x93", "\xef\xa3\x94", "\xef\xa3\x95", "\xef\xa3\x96", "\xef\xa3\x97", "\xef\xa3\x98", "\xef\xa3\x99", "\xef\xa3\x9a", "\xef\xa3\x9b", "\xef\xa3\x9c", "\xef\xa3\x9d", "\xef\xa3\x9e", "\xef\xa3\x9f", "\xef\xa3\xa0", "\xef\xa3\xa1", "\xef\xa3\xa2", "\xef\xa3\xa3", "\xef\xa3\xa4", "\xef\xa3\xa5", "\xef\xa3\xa6", "\xef\xa3\xa7",
    "\xef\xa3\xa8", "\xef\xa3\xa9", "\xef\xa3\xaa", "\xef\xa3\xab", "\xef\xa3\xac", "\xef\xa3\xad", "\xef\xa3\xae", "\xef\xa3\xaf", "\xef\xa3\xb0", "\xef\xa3\xb1", "\xef\xa3\xb2", "\xef\xa3\xb3", "\xef\xa3\xb4", "\xef\xa3\xb5", "\xef\xa3\xb6", "\xef\xa3\xb7", "\xef\xa3\xb8", "\xef\xa3\xb9", "\xef\xa3\xba", "\xef\xa3\xbb", "\xef\xa3\xbc", "\xef\xa3\xbd", "\xef\xa3\xbe", "\xef\xa3\xbf",
);

my $bn_var_arg;

sub create_target_phrase {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $ns, $key, $phrase ) = @_;

    ####
    # TODO: This logic basically is item #4 in rt 78989 (in this case passing it \&_klingman_text).
    #       It would need to deal w/ embedded methods and embedded arguments.
    #           We are not too worried about those here because we just want Klingon everywhere!
    ####

    $bn_var_arg ||= Cpanel::CPAN::Locale::Maketext::Utils::Phrase::get_bn_var_regexp();
    my $target_phrase = '';
    for my $piece ( @{ Cpanel::CPAN::Locale::Maketext::Utils::Phrase::phrase2struct($phrase) } ) {
        if ( !ref($piece) ) {
            $target_phrase .= _klingman_text($piece);
        }
        else {
            my @list = @{ $piece->{'list'} };    # copy it, do not modify it

            if ( $piece->{'type'} eq 'meth' ) {  # normally we do not want to touch asis but we do want to w/ Klingon
                if ( $list[0] eq 'asis' ) {
                    @list[ 1 .. $#list ] = map { _klingman_text("$_") } @list[ 1 .. $#list ];
                }
                elsif ( $list[0] eq 'output' && $list[1] =~ m/\Aasis/ ) {
                    @list[ 2 .. $#list ] = map { _klingman_text("$_") } @list[ 2 .. $#list ];
                }

                # else { print "DEBUG: pass through type ($piece->{'orig'})\n\tin: $phrase\n"; }

            }
            elsif ( $piece->{'type'} eq 'basic' ) {
                if ( $list[0] eq 'output' ) {
                    if ( $list[1] =~ m/\A(?:underline|strong|em|class|attr|inline|block|sup|sub)\z/ ) {
                        $list[2] = _klingman_text( $list[2] ) if $list[2] !~ m/\A$bn_var_arg\z/o;    # this can be basic instead of basic_var if there is an attribute to do

                        my $donext = 0;
                        for my $idx ( 3 .. $#list ) {
                            if ($donext) {
                                $list[$idx] = _klingman_text( $list[$idx] );
                                $donext = 0;
                            }
                            else {
                                $donext = 1 if $list[$idx] =~ m/\A(?:alt|title)\z/;
                            }
                        }
                    }
                    elsif ( $list[1] =~ m/\A(?:img|abbr|acronym)\z/ ) {
                        $list[2] = _klingman_text( $list[2] ) if $list[2] !~ m/\A$bn_var_arg\z/o;    # if is for output,img,_1
                        $list[3] = _klingman_text( $list[3] );

                        my $donext = 0;
                        for my $idx ( 4 .. $#list ) {
                            if ($donext) {
                                $list[$idx] = _klingman_text( $list[$idx] );    # these should be part of the phrase and not passed in!
                                $donext = 0;
                            }
                            else {
                                $donext = 1 if $list[$idx] =~ m/\A(?:alt|title)\z/;
                            }
                        }
                    }
                    elsif ( $list[1] eq 'url' ) {

                        # phrase checker already tells us this:
                        # warn "Please pass in the URL to output,url: $piece->{'orig'}\n\tin: $phrase\n" if $list[2] !~ m/\A$bn_var_arg\z/o

                        if ( @list > 3 ) {

                            # Since we do not have access to the arguments we can not tell if a trailing variable is a string or a hashref (like we can at runtime)
                            # That is not normally a problem except under one circumstance which we want to warn about and move on instead of die()ing
                            my $ambiguous_url = 0;
                            if ( $list[-1] =~ m/\A$bn_var_arg\z/o && @list > 4 && ( -1 == index( $list[3], ' ' ) ) ) {    # cheap hack since attribute keys don't have spaces
                                warn "Possible ambiguous use of trailing variable in output,url: $piece->{'orig'}\n";
                                $ambiguous_url = 1;
                            }

                            my $args_hash_starting_idx = 3;
                            if ( @list % 2 ) {                                                                            # output url _1 foo bar == args even
                                if ($ambiguous_url) {
                                    $list[3] = _klingman_text( $list[3] ) if $list[3] !~ m/\A$bn_var_arg\z/o;
                                    $args_hash_starting_idx = 4;
                                }
                                elsif ( $list[-1] =~ m/\A$bn_var_arg\z/o && @list > 4 && ( -1 != index( $list[3], ' ' ) ) ) {    # cheap hack since attribute keys don't have spaces
                                    $list[3] = _klingman_text( $list[3] ) if $list[3] !~ m/\A$bn_var_arg\z/o;
                                    $args_hash_starting_idx = 4;
                                }

                            }
                            else {                                                                                               # output url _1 foo bar baz == args odd
                                if ( !$ambiguous_url ) {
                                    $list[3] = _klingman_text( $list[3] ) if $list[3] !~ m/\A$bn_var_arg\z/o;
                                    $args_hash_starting_idx = 4;
                                }
                            }

                            my $donext = 0;
                            for my $idx ( $args_hash_starting_idx .. $#list ) {
                                if ($donext) {
                                    last if $idx == $#list && $list[$idx] =~ m/\A$bn_var_arg\z/o;
                                    $list[$idx] = _klingman_text( $list[$idx] );    # these should be part of the phrase and not passed in!
                                    $donext = 0;
                                }
                                else {
                                    $donext = 1 if $list[$idx] =~ m/\A(?:alt|title|html|plain)\z/;
                                }
                            }
                        }
                    }
                    else {
                        warn "Unhandled basic output() type: $piece->{'orig'}\n\tin: $phrase\n";
                    }
                }
                else {
                    warn "Unhandled basic type: $piece->{'orig'}\n\tin: $phrase\n";
                }

            }
            elsif ( $piece->{'type'} eq 'complex' ) {
                if ( $list[0] =~ m/\A(quant|numerate|boolean|is_future|is_defined)\z/ ) {
                    @list[ 2 .. $#list ] = map { _klingman_text("$_") } @list[ 2 .. $#list ];
                }
                else {
                    warn "Unhandled complex type: $piece->{'orig'}\n\tin: $phrase\n";
                }
            }

            # else { print "DEBUG: pass through type ($piece->{'orig'})\n\tin: $phrase\n"; }

            $target_phrase .= '[' . join( ",", @list ) . ']';
        }
    }

    return $target_phrase;
}

sub get_i_tag_config_hr {
    return {
        display_name    => "",
        fallback_locale => 'en',
    };
}

sub _klingman_text {
    my ($text) = @_;

    # should be safe since we are operating on byte strings, if not then we want warnings/errors to alert us to the problem
    utf8::decode($text);    # turn piece into Unicode …

    return join(
        '',
        map {
            $_ eq ' ' ? ' ' :    #
              $_ eq "\x{00A0}"
              ? "\xc2\xa0"       # non-breaking space is invisible so grapheme the bytes to make it visible
              : $klingon_unicode_range_bytes_list[ rand @klingon_unicode_range_bytes_list ]
        } split '',
        $text
    );
}

1;
