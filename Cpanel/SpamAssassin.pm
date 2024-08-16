package Cpanel::SpamAssassin;

# cpanel - Cpanel/SpamAssassin.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DataStore            ();
use Cpanel                       ();
use Cpanel::Locale               ();
use Cpanel::SpamAssassin::Config ();
use Cpanel::StringFunc::Case     ();

use HTML::Entities ();

my $locale;

sub SpamAssassin_init { return 1; }

*get_config_option = *Cpanel::SpamAssassin::Config::get_config_option;

sub SpamAssassin_config {
    return if !Cpanel::hasfeature('spamassassin');

    my (%OPTIONS);
    my (%OPTIONU);
    my (%OPTIONCT);
    my (%OPTIONFORMAT);
    my (%OPTIONDESC);

    my $subrewrite = 0;
    my $saopt      = 0;
    open( SPAMO, '<', '/usr/local/cpanel/etc/spamassassin.options' );
    while (<SPAMO>) {
        next if (/^\#/);
        $saopt .= $_;
    }
    close(SPAMO);

    my @SPAMOPTS = split( /\;\;/, $saopt );
    my %SEENOPT;
    my $locale_tag = 'en';

    if (@SPAMOPTS) {
        $locale ||= Cpanel::Locale->get_handle();
        $locale_tag = $locale->get_language_tag();
    }
    my $OPTLOCALE = Cpanel::DataStore::fetch_ref("/usr/local/cpanel/etc/.locale.spamassassin.options/$locale_tag.yaml");

    foreach (@SPAMOPTS) {
        s/\n/ /g;
        s/^\s*//g;
        s/^0//g;
        my ( $tag, $count, $desc, $format, $default ) = split( /=/, $_ );
        $OPTIONS{$tag}      = $default;
        $OPTIONU{$tag}      = 0;
        $OPTIONCT{$tag}     = $count;
        $OPTIONFORMAT{$tag} = $format;
        $OPTIONDESC{$tag}   = $OPTLOCALE->{$tag} || $desc;
    }

    if ( !-e "$Cpanel::homedir/.spamassassin" ) {
        mkdir( "$Cpanel::homedir/.spamassassin", 0700 );
    }

    my (%OPTCNT);
    my (@SCC);

    open( SC, "$Cpanel::homedir/.spamassassin/user_prefs" );
    while (<SC>) {
        push( @SCC, $_ );

        next if (/^\s+/);
        next if (/^\#/);
        my ( $option, $value, @additional_values ) = parse_config_line($_);
        my $value2 = join ' ', @additional_values;
        if ( $option eq "score" ) {
            if ( $value =~ /^(\-?\d+[\.]?[\d]{0,2})[\d]*$/ ) {
                $value = $1;
            }
            else {
                $option = Cpanel::StringFunc::Case::ToLower($option);
                $value2 =~ /^(\-?\d+[\.]?[\d]{0,2})[\d]*$/;
                $value = $1;
            }
        }
        elsif ( $option eq "rewrite_header" ) {
            if ( $value =~ /SUBJECT|FROM|TO/i ) {
                $option = $option . " " . $value;
                $option = Cpanel::StringFunc::Case::ToLower($option);
                $value  = $value2;
                $value2 = "";
            }
            else {
                $option = "";
                $value  = "";
            }
        }
        elsif ( $option eq "required_hits" ) {
            $option = "required_score";
        }
        elsif ( $option eq "rewrite_subject" ) {
            if ( $value == 1 ) {
                $subrewrite = 1;
            }
            $option = "";
            $value  = "";
        }
        elsif ( $option eq "subject_tag" && $subrewrite == 1 ) {
            $option = "rewrite_header subject";
            $value  = $value . " " . $value2;
            $value2 = "";
        }
        elsif ( $option eq "subject_tag" ) {
            $option = "";
            $value  = "";
        }
        else {
            $option = Cpanel::StringFunc::Case::ToLower($option);
        }
        next if ( $option eq "" );
        $OPTCNT{$option}++;
    }
    close(SC);
    $subrewrite = 0;

    foreach ( sort @SCC ) {
        next if (/^\s+/);
        next if (/^\#/);

        my ( $option, $value, @additional_values ) = parse_config_line($_);
        my $value2 = join ' ', @additional_values;

        if ( should_skip($option) ) {
            next();
        }
        if ( $option eq "score" ) {
            if ( $value =~ /^(\-?\d+[\.]?[\d]{0,2})[\d]*$/ ) {
                $value = $1;
            }
            else {
                $option = Cpanel::StringFunc::Case::ToLower($option);
                $value2 =~ /^(\-?\d+[\.]?[\d]{0,2})[\d]*$/;
            }
        }
        elsif ( $option eq "rewrite_header" ) {
            if ( $value =~ /SUBJECT|FROM|TO/i ) {
                $option = $option . " " . $value;
                $option = Cpanel::StringFunc::Case::ToLower($option);
                $value  = $value2;
                $value2 = "";
            }
        }
        elsif ( $option eq "required_hits" ) {
            $option = "required_score";
        }
        elsif ( $option eq "rewrite_subject" ) {
            if ( $value == 1 ) {
                $subrewrite = 1;
            }
            $option = "";
            $value  = "";
        }
        elsif ( $option eq "subject_tag" && $subrewrite == 1 ) {
            $option = "rewrite_header subject";
            $value  = $value . " " . $value2;
            $value2 = "";
        }
        elsif ( $option eq "subject_tag" ) {
            $option = "";
            $value  = "";
        }
        else {
            $option = Cpanel::StringFunc::Case::ToLower($option);
        }
        next if ( $option eq "" );
        next if should_skip($option);

        delete $OPTIONU{$option};

        if ( !$SEENOPT{$option} ) {
            print "<tr class=\"sa-desblock\"><td colspan=2>$OPTIONDESC{$option}</td></tr>\n";
            $SEENOPT{$option} = 1;
        }

        if ( $option eq 'score' ) {
            print "<tr><td><b>${henc($option)}\t${henc($value)}</b></td><td><input type=text name=\"${henc($option)} ${henc($value)}\" value=\"${henc($value2)}\">";
        }
        elsif ( $option eq 'rewrite_header subject' ) {
            print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"${henc(stripq($value))}\">";
        }
        elsif ($value2) {
            print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"${henc($value)} ${henc($value2)}\">";
        }
        else {
            print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"${henc($value)}\">";
        }
        $OPTCNT{$option}--;
        if ( $OPTCNT{$option} == 0 ) {
            if ( $OPTIONCT{$option} eq "0" ) {
                for ( my $i = 1; $i < 5; $i++ ) {
                    print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"\"></tr>\n";
                }
            }
        }
    }

    foreach my $option ( sort keys %OPTIONU ) {
        next if ( $option eq "" );
        next if should_skip($option);

        if ( !$SEENOPT{$option} ) {
            print "<tr class=\"sa-desblock\"><td colspan=2>$OPTIONDESC{$option}</td></tr>\n";
            $SEENOPT{$option} = 1;
        }

        print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"${henc($OPTIONS{$option})}\"></td></tr>";
        if ( $OPTIONCT{$option} eq "0" ) {
            for ( my $i = 1; $i < 5; $i++ ) {
                print "<tr><td><b>${henc($option)}</b></td><td><input type=text name=\"${henc($option)}\" value=\"${henc($OPTIONS{$option})}\"></tr>\n";
            }
        }

    }

}

sub SpamAssassin_saveconfig {
    return if !Cpanel::hasfeature('spamassassin');

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    my ($form) = @_;
    my (%FORM) = %{$form};
    my ($cf);

    my (%OPTIONS);
    my (%OPTIONU);
    my (%OPTIONCT);
    my (%OPTIONFORMAT);

    my $saopt = 0;
    open( SPAMO, "/usr/local/cpanel/etc/spamassassin.options" );
    while (<SPAMO>) {
        next if (/^#/);
        $saopt .= $_;
    }
    close(SPAMO);

    my @SPAMOPTS = split( /\;\;/, $saopt );

    foreach (@SPAMOPTS) {
        s/\n/ /g;
        s/^\s*//g;
        s/^0//g;
        next if !$_;
        my ( $tag, $count, $desc, $format, $default ) = split( /=/, $_ );
        $OPTIONS{$tag}      = $default;
        $OPTIONU{$tag}      = 0;
        $OPTIONCT{$tag}     = $count;
        $OPTIONFORMAT{$tag} = $format;

        # If we use $OPTIONDESC{$tag} we should localize this like we did above.
        # $OPTIONDESC{$tag} = $desc;
    }

    open( SC, "$Cpanel::homedir/.spamassassin/user_prefs" );
    while (<SC>) {
        if ( /^[\s\t]*$/ || /^[\s\t]*\#.*$/ || should_skip( ( parse_config_line($_) )[0] ) ) {
            $cf .= $_;
        }
    }
    close(SC);

    foreach my $option ( sort keys %FORM ) {
        my $optionvalue = ${ hdec( $FORM{$option} ) };
        next if should_skip($option);
        next if ( $optionvalue eq "" );

        if ( $option =~ /^score|required_score$/i ) {
            if ( $optionvalue =~ /^(\d+[\.]?[\d]{0,2})[\d]*$/ ) {
                $optionvalue = $1;
            }
        }

        $option =~ s/\+/ /g;
        $option =~ s/-\d+//g;
        if ( $option eq 'rewrite_header subject' ) {
            $optionvalue = addq($optionvalue);
        }
        $cf .= "$option $optionvalue\n";
    }

    open( SC, ">$Cpanel::homedir/.spamassassin/user_prefs" );
    print SC $cf;
    close(SC);
}

# Attempt to parse a config line while respecting quoted strings wherever they appear. If the
# line cannot be parsed properly due to a syntax error, fall back to crude parsing which is
# still adequate for passing the data through the form.
sub parse_config_line {
    my $line = shift;

    my @pieces = $line =~ m{
        \s*              # ignore leading whitespace before any piece
        (   "[^"]+"      # double-quoted string which may contain whitespace
          | '[^']+'      # single-quoted string which may contain whitespace
          | [^"']\S*     # non-quoted string which may not contain whitespace
          | ["'].+       # unbalanced quotes suck everything to the right in and will result in a validation failure
        )
        (?: \s+ | \z )   # a piece must be followed either by whitespace or by the end of the line
    }gx;

    # discard inline comments
    for ( 0 .. $#pieces ) {
        if ( $pieces[$_] =~ /^#/ ) {
            @pieces = splice @pieces, 0, $_;
            last;
        }
    }

    if ( !validate_pieces( \@pieces ) ) {
        @pieces = split /\s+/, $line, 3;
    }
    return @pieces;
}

sub validate_pieces {
    my $pieces = shift;
    for (@$pieces) {
        return if !$_;
        if ( /^"/ && !/"$/ || /^'/ && !/'$/ ) {
            print "WARNING: Unbalanced quotes in <b>${henc($_)}</b><BR>\n";
            return;
        }
    }
    return 1;
}

sub henc { return \HTML::Entities::encode_entities(@_) }
sub hdec { return \HTML::Entities::decode_entities(@_) }

# strip outer quotes from rewrite_header subject before displaying in frontend
sub stripq {
    my $string = shift;
    $string =~ s/^"(.+)"$/$1/ or $string =~ s/^'(.+)'$/$1/;
    return $string;
}

# re-add outer quotes to rewrite_header subject before saving to disk, but strip inner quotes to avoid breaking file syntax
sub addq {
    my $string = shift;
    $string =~ tr/"//d;
    return qq{"$string"};
}

sub should_skip {
    my $option = shift;
    return ( $option =~ /rewrite/i || $option eq 'rewrite_subject' || $option eq 'rewrite' || $option eq 'subject_tag' );
}

1;
