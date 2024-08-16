package Cpanel::Locale::Utils::Tool::Where;

# cpanel - Cpanel/Locale/Utils/Tool/Where.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Text::Extract::MaketextCallPhrases 0.91 ();

use Cpanel                   ();
use Cpanel::SafeRun::Dynamic ();

sub subcmd {
    my ( $app, $phrase, @args ) = @_;

    my $given_out_fh = 0;
    my $out_fh;
    if ( ref( $args[0] ) ) {
        $given_out_fh = 1;
        $out_fh       = shift(@args);
    }

    die "'where' only takes one argument: a string to look for\n" if @args;

    die "'where' requires a string to look for\n" if !defined $phrase || $phrase eq '';

    my $raw     = 0;    # TODO ? from flag ?
    my $context = 2;    # TODO ? from flag ?

    my $in_ignore       = 0;
    my $had_first_match = 0;
    my @match_buffer;

    # TODO: ? my $pager = $ENV{'PAGER'} || 'less'; ? what if PAGER is an alias? what if it is something that does not support -r the same way? etc
    if ( !$given_out_fh ) {
        open( $out_fh, '|-', 'less', '-r' ) || die "Pipe to less failed: $!";
    }

    Cpanel::SafeRun::Dynamic::livesaferun(
        'prog'      => [ qw(git grep -n -i -C), $context, '--color=always', '-F', $phrase, qw(-- .) ],
        'formatter' => sub {
            my ($line) = @_;

            if ( $line =~ m{^(?:locale/|Cpanel/CPAN/)} ) {    # TODO ? share ignore list w/ find()?
                $in_ignore++;
                return '';
            }
            else {
                if ( $in_ignore && $line =~ m/^\S+--\S+\n/ ) {
                    $in_ignore = 0;
                    return '';
                }
            }

            return $line if $raw;

            if ( $line =~ m/^(\S+--\S+\s*\n)/ ) {
                my $dash = $1;
                _process_chunk( \@match_buffer, $phrase, $out_fh, $had_first_match, $dash, $context );
            }
            else {
                push @match_buffer, $line;
            }

            return '';
        }
    );

    # This ensures that the 'last' result of the git grep is processed. The last result is typically 'skipped'
    # above, because it doesn't end with a '--'
    if (@match_buffer) {
        _process_chunk( \@match_buffer, $phrase, $out_fh, $had_first_match, '--', $context );
    }

    close($out_fh) if !$given_out_fh;

    return;
}

sub _process_chunk {
    my ( $match_buffer, $unescaped_phrase, $out_fh, $had_first_match, $dash, $context ) = @_;

    return unless scalar @{$match_buffer};

    # If the 'git grep' result is from one of the dynamicui.conf files,
    # then mark it as a translated string.
    my $theme = $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;
    if ( $match_buffer->[0] =~ m{^base/frontend/$theme/dynamicui\.conf} ) {
        print {$out_fh} @{$match_buffer};
        @$match_buffer = ();
        return '';
    }

    # If the match_buffer has more than 4 lines, then it means we can reliably "cut" out the 2 lines of
    # context text from the 'git grep' output.
    #
    # However if the match buffer is less than or equal to 4 lines, then it means the 'context' lines
    # were not populated (ex: when the string match occurs in the first 2 lines of the file), so we should
    # consider using the full chunk when extracting the match.
    my @chunk_lines;
    if ( scalar @{$match_buffer} > 4 ) {
        @chunk_lines = @{$match_buffer}[ $context .. scalar @{$match_buffer} - $context ];
    }
    else {
        @chunk_lines = @{$match_buffer};
    }

    my $chunk = '';
    for my $match_line (@chunk_lines) {
        my $copy = $match_line;               # do not want to modify @match_buffer via alias
        $copy =~ s{ \e\[ [\d;]* m }{}xmsg;    # Term::ANSIColor::colorstrip() v4.02
        $copy =~ s/^\S+(.)[0-9]+\1//;         # trim path/line label
        $chunk .= $copy;
    }

    #print "---- START\n$chunk\n---- END\n";

    my $res = Text::Extract::MaketextCallPhrases::get_phrases_in_text(
        $chunk,
        {
            'cpanel_mode' => 1,    # any new tokens we need to parse for need added to the upstream module’s cpanel_mode in order to k    eep all consumers cpanel or not consistent and universal
        }
    );

    my @matches = map { defined $_->{'phrase'} && $_->{'phrase'} =~ m/\Q$unescaped_phrase\E/i ? $_ : () } @{$res};
    my @return;
    if (@matches) {
        $dash = '' if !$had_first_match;
        $had_first_match++;
        @return = ( $dash, @$match_buffer );
    }

    @$match_buffer = ();
    print {$out_fh} @return;
    return '';
}

1;
