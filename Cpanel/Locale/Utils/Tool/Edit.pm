package Cpanel::Locale::Utils::Tool::Edit;

# cpanel - Cpanel/Locale/Utils/Tool/Edit.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Slurper                                       ();
use IO::Prompt                                            ();
use File::Temp                                            ();
use File::ReadBackwards                                   ();
use Text::Extract::MaketextCallPhrases 0.91               ();
use Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel ();

use Cpanel::Encoder::utf8 ();
use Cpanel::LoadFile      ();
use Cpanel::Locale::Utils::Tool;
use Cpanel::Locale::Utils::Tool::Find ();
use Cpanel::SafeStorable              ();
use Cpanel::StringFunc::Trim          ();
use Cpanel::PwCache                   ();

my $default_editor = 'nano';

sub subcmd {
    my ( $app, $resource, @args ) = @_;

    if ( $resource eq '-' ) {
        print "Processing files provided via STDIN …\n";
        $resource = [<STDIN>];
        chomp( @{$resource} );
    }

    if ( !$ENV{'EDITOR'} ) {
        $ENV{'EDITOR'} = $default_editor;
        print style( "warn", "EDITOR not set, defaulting to “$default_editor” …" ) . "\n";
    }

    my %flags;
    @flags{qw(all passed warnings violations queue verbose no-git-check extra-filters)} = ();
    for my $flag (@args) {
        my $dashless = $flag;
        $dashless =~ s/^--//;
        die "'edit' does not know about '$flag'" if !exists $flags{$dashless};
    }

    my $opts = {};
    for my $bool ( keys %flags ) {
        $opts->{$bool} = grep( /^--$bool$/, @args ) ? 1 : 0;
    }

    # if none were given then do them all
    if ( !$opts->{'passed'} && !$opts->{'warnings'} && !$opts->{'violations'} ) {
        $opts->{'passed'}     = 1;
        $opts->{'warnings'}   = 1;
        $opts->{'violations'} = 1;
    }

    $opts->{'return_hash'}              = 1;
    $opts->{'verbose_with_return_hash'} = 1;

    Cpanel::Locale::Utils::Tool::pid_file_check();
    Cpanel::Locale::Utils::Tool::session_sanity_init();
    my %phrases = Cpanel::Locale::Utils::Tool::Find::run( $resource, $opts );

    Cpanel::Locale::Utils::Tool::do_pre_walk_summary( \%phrases );

    my $counts = Cpanel::Locale::Utils::Tool::get_counts_hr();

    # Processing through each phrase
    Cpanel::Locale::Utils::Tool::walk_hash(
        \%phrases,
        sub {
            my ( $phrase, $instances ) = @_;
            $counts->{'total'}++;
            $counts->{ $instances->[0]{'cpanel:checker:style'} }++;
            return walk_hash_output_for_edit( $phrase, $instances, $opts );
        },
        1
    );

    if ( exists $opts->{'file_edits'} && ref( $opts->{'file_edits'} ) ) {
        Cpanel::Locale::Utils::Tool::session_sanity_check();
        do_file_edits( $opts->{'file_edits'}, $opts );
    }
    else {
        print style( 'info', 'There are no edits to do.' ) . "\n\n";
    }

    Cpanel::Locale::Utils::Tool::display_counts_hr_summary($counts);
    return;
}

sub walk_hash_output_for_edit {
    my ( $phrase, $instances, $opts ) = @_;

    local $opts->{'phrase_info'}             = [];
    local $opts->{'do_session_sanity_check'} = 1;
    my $tpds_instance_count = Cpanel::Locale::Utils::Tool::Find::walk_hash_output( $phrase, $instances, $opts );
    print "\n";

    if ( -f _skipped_phrases_file() ) {
        my $skipped_phrases = Cpanel::SafeStorable::retrieve( _skipped_phrases_file() );
        Cpanel::Encoder::utf8::encode( my $utf8_encoded_phrase = $phrase );
        if ( $skipped_phrases->{$utf8_encoded_phrase} ) {
            print indent(1) . style( 'info', 'The system will skip this phrase because it is in your local permanent skip list' ) . "\n";
            return;
        }
    }

  EDIT_CHOICE:
    my $choice_char = Cpanel::Locale::Utils::Tool::prompt_choice(
        "Would you like to revise the phrase?",
        [
            {
                'char' => 'y',
                'text' => 'yes',
            },
            {
                'char' => 'Y',
                'text' => q{Yes, and don't ask about revised version},
            },
            {
                'char' => 'n',
                'text' => 'no',
            },
            {
                'char' => 'N',
                'text' => q{No, and don't ask again},
            },
            {
                'char' => 'q',
                'text' => 'quit editing',
            },
        ]
    );

    if ( $choice_char eq 'n' ) {
        if ( $opts->{'queue'} ) {
            if ( Cpanel::Locale::Utils::Tool::prompt_yes_no("Would you like to queue this phrase ?") ) {
                Cpanel::Locale::Utils::Tool::ensure_is_in_queue($phrase);
                print style( 'info', "Unedited phrase was added to the queue." ) . "\n";
            }
        }
    }
    elsif ( $choice_char eq 'q' ) {
        my $choice_char = Cpanel::Locale::Utils::Tool::prompt_choice(
            "Save any changes you’ve made so far?",
            [
                {
                    'char' => 'y',
                    'text' => 'yes',
                },
                {
                    'char' => 'n',
                    'text' => 'no',
                },
                {
                    'char' => 'c',
                    'text' => 'cancel',
                },
            ]
        );
        if ( $choice_char eq 'n' ) {
            print "Exiting per your request …\n";
            exit;
        }
        elsif ( $choice_char eq 'c' ) {
            goto EDIT_CHOICE;    # go back to the prompt right before this, simple
        }
        else {
            print "Skipping directly to editing …\n";
            return "0E0";        # this RV will stop the loop this is inside of
        }
    }
    elsif ( $choice_char eq 'y' or $choice_char eq 'Y' ) {

        my $reprompt;
      EDIT_PROMPT:
        while (1) {
            my $replacement_text = get_replacement_text( $reprompt || $phrase, { indent => 2 }, @{ $opts->{'phrase_info'} } );

            if ( $choice_char eq 'Y' ) {
                _permanently_skip_phrase($replacement_text);
            }

            my %apply_rest;
            my %skip_rest;
            if ( $replacement_text && $replacement_text ne $phrase ) {
                if ( validate_phrase( $replacement_text, { indent => 3, 'extra-filters' => $opts->{'extra-filters'} } ) ) {
                    print indent(2) . style( 'good', 'Your new version validates.' ) . "\n";

                    my $remaining_count = @{$instances};
                  INSTANCE:
                    for my $res_hr ( @{$instances} ) {
                        $remaining_count--;

                        if ( $res_hr->{'heredoc'} ) {
                            print indent() . style( "info", "Skipping heredoc instance …" ) . "\n";
                            next INSTANCE;
                        }

                        if ( $phrase =~ m/\n/ || exists $res_hr->{'type'} && $res_hr->{'type'} eq 'multiline' ) {
                            print indent() . style( "warn", "Skipping multiline instance …" ) . "\n";
                            next INSTANCE;
                        }

                        $opts->{'file_edits'}{ $res_hr->{'file'} }{'instance_count'}{$phrase}++;

                        next INSTANCE if exists $skip_rest{ $res_hr->{'file'} }{$phrase};

                        my $instance_data_hr = {
                            'remaining_count'  => $remaining_count,
                            'instances'        => $instances,
                            'phrase'           => $phrase,
                            'replacement_text' => $replacement_text,
                        };
                        my $res = $apply_rest{ $res_hr->{'file'} }{$phrase} ? 'Apply' : _do_instance_prompt( $res_hr, $instance_data_hr );

                        if ( $res =~ m/Apply.*remaining instances in this file/ ) {
                            $apply_rest{ $res_hr->{'file'} }{$phrase}++;
                        }
                        elsif ( $res =~ m/Skip.*remaining instances in this file/ ) {
                            $skip_rest{ $res_hr->{'file'} }{$phrase}++;
                        }

                        if ( $res =~ m/^Apply/ ) {
                            $res_hr->{'cpanel:replacement_text'} = $replacement_text;
                            $opts->{'file_edits'}{ $res_hr->{'file'} }{'edit_count'}{$phrase}++;
                            push @{ $opts->{'file_edits'}{ $res_hr->{'file'} }{'edits'} }, $res_hr;
                        }
                    }

                    last EDIT_PROMPT;
                }
                else {
                    print indent(2) . style( "error", 'The new version does not validate, sorry.' ) . "\n";
                    if ($@) {
                        my $err = $@;
                        $err =~ s/ at \S+ line \d+.\s*$//;
                        print indent(3) . style( 'info', Cpanel::StringFunc::Trim::ws_trim($err) ) . "\n";
                    }

                    if ( Cpanel::Locale::Utils::Tool::prompt_yes_no( indent() . "Would you like to edit it again?" ) ) {
                        $reprompt = $replacement_text;
                        next EDIT_PROMPT;
                    }
                    else {
                        last EDIT_PROMPT;
                    }
                }
            }
            else {
                if ( !$replacement_text ) {
                    print indent(2) . style( "warn", 'No phrase given, skipping.' ) . "\n";
                    if ( $opts->{'queue'} ) {
                        if ( Cpanel::Locale::Utils::Tool::prompt_yes_no("Would you like to queue the unedited phrase?") ) {
                            Cpanel::Locale::Utils::Tool::ensure_is_in_queue($phrase);
                            print style( 'info', "Unedited phrase was added to the queue." ) . "\n";
                        }
                    }
                }
                elsif ( $replacement_text eq $phrase ) {
                    print indent(2) . style( "warn", 'Phrase not changed, skipping.' ) . "\n";
                    if ( $opts->{'queue'} ) {
                        if ( Cpanel::Locale::Utils::Tool::prompt_yes_no("Would you like to queue the unedited phrase?") ) {
                            Cpanel::Locale::Utils::Tool::ensure_is_in_queue($phrase);
                            print style( 'info', "Unedited phrase was added to the queue." ) . "\n";
                        }
                    }
                }

                last EDIT_PROMPT;
            }
        }
    }
    elsif ( $choice_char eq 'N' ) {
        _permanently_skip_phrase($phrase);
    }
    return;
}

sub do_file_edits {
    my ( $file_edits, $opts ) = @_;

    print style( 'info', 'Beginning edits …' ) . "\n";
    my %queued;

  FILE:
    for my $file ( keys %{$file_edits} ) {
        if ( !exists $file_edits->{$file}{'edits'} ) {
            print "No edits in “$file”.\n";    # so, how did we get here?
            next FILE;
        }

        # now that we have a complete list of edits for every file build line number lookup w/ instances in order for this particular file
        my %line_edits;
        my %did_fyi_for_file;
        for my $edit ( sort { $b->{'line'} <=> $a->{'line'} || $b->{'offset'} <=> $a->{'offset'} } @{ $file_edits->{$file}{'edits'} } ) {
            push @{ $line_edits{ $edit->{'line'} } }, $edit;

            # print "Editing $file line $edit->{'line'} offset $edit->{'offset'}:\n";
            # print "\tPhrase: $edit->{'phrase'}\n";
            # print "\tNewStr: $edit->{'cpanel:replacement_text'}\n\n";
        }

        print indent() . "Editing “$file” …\n";

        # now edit:
        edit_in_reverse(
            $file,
            sub {
                my ( $line_number, $line_sr ) = @_;

                if ( exists $line_edits{$line_number} ) {
                    my $new_line = ${$line_sr};

                    for my $edit ( @{ $line_edits{$line_number} } ) {

                        print indent(2) . "Editing line $edit->{'line'} offset $edit->{'offset'}.\n";

                        if ( $opts->{'verbose'} ) {
                            print indent(3) . "Original: $edit->{'phrase'}\n";
                            print indent(3) . "Replace : $edit->{'cpanel:replacement_text'}\n";
                        }

                        # Just in case the caller didn't sanitize properly:
                        if ( $edit->{'heredoc'} ) {
                            print indent(3) . style( "warn", "Sorry, this tool can not currently edit heredoc instances." ) . "\n";
                            next;
                        }
                        elsif ( $edit->{'phrase'} =~ m/\n/ || exists $edit->{'type'} && $edit->{'type'} eq 'multiline' ) {
                            print indent(3) . style( "warn", "Sorry, this tool can not currently edit multiline instances." ) . "\n";
                            next;
                        }

                        if ( !$edit->{'quote_before'} ) {
                            print indent(3) . style( "warn", "Sorry, I can not tell how this was quoted so I don’t want to risk a mis-edit." ) . "\n";
                            next;
                        }

                        my $pre = substr( $new_line, 0, $edit->{'offset'} + length( $edit->{'quote_before'} ) );
                        my $pst = substr( $new_line, $edit->{'offset'} + length("$edit->{'quote_before'}$edit->{'original_text'}") );

                        # We don't use $pst in this if because it can change!
                        if ( "$pre$edit->{'original_text'}$edit->{'quote_after'}" ne substr( ${$line_sr}, 0, length("$pre$edit->{'original_text'}$edit->{'quote_after'}") ) ) {
                            print indent(3) . style( "warn", "Sorry, it looks like this line has changed out from under you." ) . "\n";
                            next;
                        }

                        # not fool proof if false but definetly a problem if true:
                        if ( substr( $pst, 0, length( $edit->{'quote_after'} ) ) ne $edit->{'quote_after'} ) {
                            print indent(3) . style( "warn", "Sorry, it looks like I was unable to determine the correct edit position." ) . "\n";
                            next;
                        }
                        my $new = $edit->{'cpanel:replacement_text'};

                        # probably a NO-OP ATM since it won’t allow ' or " markup chars, but just in case the caller tries to slip one in
                        $new =~ s/$edit->{'quote_before'}/\\$edit->{'quote_before'}/g if $edit->{'quote_before'} eq '"' || $edit->{'quote_before'} eq "'";

                        # d([$edit->{'original_text'}, $edit->{'quote_before'}, $edit->{'cpanel:replacement_text'} ], [$pre, $new, $pst]);
                        $new_line = "$pre$new$pst";

                        if ( !exists $queued{ $edit->{'cpanel:replacement_text'} } ) {
                            if ( $opts->{'queue'} ) {
                                Cpanel::Locale::Utils::Tool::ensure_is_in_queue( $edit->{'cpanel:replacement_text'} );    # die()s if there is a problem
                                $queued{ $edit->{'cpanel:replacement_text'} }++;
                                print indent(4) . style( "good", "Ensured new version is in queue." ) . "\n";
                            }
                            else {
                                $queued{ $edit->{'cpanel:replacement_text'} } = undef;                                    # different value in case we care to check someday
                            }

                        }

                        if ( !$did_fyi_for_file{ $edit->{'phrase'} }++ && $file_edits->{$file}{'instance_count'}{ $edit->{'phrase'} } == $file_edits->{$file}{'edit_count'}{ $edit->{'phrase'} } ) {

                            # TODO: remove $phrase from queue when appropriate (e.g. maybe we edited all instances in this resource
                            #  but what if resource is not “.” or otherwise is not universal (e.g. TPDS instances)).
                            #  So for now we FYI the first time we edit all instances in a file since it is indicative of a global change.
                            print indent(2) . style( "warn", "Don’t forget to remove the original ($edit->{'phrase'}) from queue if appropriate." ) . "\n" unless $opts->{'no-remove-queue-reminder'};
                        }
                    }

                    ${$line_sr} = $new_line;
                }
            }
        );
    }

    print "\n";
    return;
}

sub edit_in_reverse {
    my ( $file, $line_handler ) = @_;

    my $tw   = File::Temp->new();
    my $path = $tw->filename;

    my $rh = File::ReadBackwards->new($file);
    if ( !$rh ) {
        print indent(1) . style( "error", "Could not read “$file” ($!), none of its edits can be applied." ) . "\n";
        return;
    }

    # get the current line number
    my $cur_line_number = ( Cpanel::LoadFile::load($file) =~ tr/\n// );
    $cur_line_number++;    # increment it by one so that the adjustment in while() works

    # read it in backwards, operating on the line numbers we need, and write edits to temp file in backwards order
    my $first_loop             = 1;
    my $added_trailing_newline = 0;
    my $line;              # buffer
    while ( defined( $line = $rh->readline() ) ) {
        $cur_line_number--;

        # this is required in order to keep eof-w/out-\n from causing the next to last line from becoming part
        # of the last line and thus throwing the line count off by one (and being placed after it instead of before)
        if ($first_loop) {
            $first_loop = 0;
            if ( $line !~ m/\n/ ) {
                $cur_line_number++;    # without this we’d be operating on the wrong line later in the loop
                $added_trailing_newline = 1;
                $line .= "\n";
            }
        }

        # d("Processing line $cur_line_number: $line");
        eval { $line_handler->( $cur_line_number, \$line ) };
        return if $@;

        print {$tw} $line;
    }
    close($tw);
    $rh->close();

    # read in tmp file backwards and re-write original to bring in edits and restore order:
    my $rn = File::ReadBackwards->new($path);
    if ( !$rn ) {
        print indent(1) . style( "error", "Could not read temporary working file for “$file” ($path: $!), none of its edits can be applied." ) . "\n";
        return;
    }

    my $wn;
    if ( !open( $wn, '>', $file ) ) {
        print indent(1) . style( "error", "Could not write “$file” ($!), none of its edits can be applied." ) . "\n";
        return;
    }

    while ( defined( $line = $rn->readline() ) ) {
        print {$wn} $line;
    }

    if ($added_trailing_newline) {
        seek( $wn, -1, 2 );
        truncate( $wn, tell($wn) );
    }

    close $wn;
    $rn->close();

    return 1;
}

sub get_help_text {
    return <<'END_HELP';
Revise phrases found in the specified resource.

  --all            Include known phrases in addition to unknown phrases
  --verbose        Include additional information
  --extra-filters  Enable the phrase checker’s extra filters
  --queue          Enables options for queueing phrases
                   Phrases can be queued if not edited, edited but not changed,
                   or edited and applied to the source files.

  --no-git-check   If the given resource is a directory include all files in
                   the iteration even if they are outside of the repository.

  By default the following flags are all in effect unless one or more are passed in:

  --passed      Edit phrases that passed the phrase checker with no warnings
  --warnings    Edit phrases that passed the phrase checker with warnings
  --violations  Edit phrases that failed the phrase checker
END_HELP
}

sub validate_phrase {
    my ( $phrase, $setup ) = @_;
    $setup->{'indent'} ||= 3;

    my $phrase_checker = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel->new_source( { 'run_extra_filters' => $setup->{'extra-filters'} } ) || die "Could not create normalization object";

    my $result = eval { $phrase_checker->normalize($phrase) };
    return if !$result;

    my $error_type = { 'warning' => 0, 'violation' => 1 };

    if ( $result->get_violation_count() ) {
        Cpanel::Locale::Utils::Tool::Find::_walk_filter( $result, $error_type->{'violation'}, $setup->{'indent'} );
        return;
    }
    elsif ( $result->get_warning_count() ) {
        print indent(2) . style( 'bold', 'New Version: ' ) . style( 'highlight', $phrase ) . "\n\n";
        Cpanel::Locale::Utils::Tool::Find::_walk_filter( $result, $error_type->{'warning'}, $setup->{'indent'} );
        my $warning_ok = Cpanel::Locale::Utils::Tool::prompt_choice(
            "Is the warning OK to leave in place?",
            [
                {
                    'char' => 'y',
                    'text' => 'yes',
                },
                {
                    'char' => 'n',
                    'text' => 'no',
                },
            ]
        );
        return 1 if defined $warning_ok && $warning_ok eq 'y';
        return;
    }

    return 1;
}

sub get_replacement_text {
    my ( $current, $setup, @info_arr ) = @_;

    $setup->{'indent'} ||= 3;

    return '' if !Cpanel::Locale::Utils::Tool::is_interactive();

    if ( !$ENV{'EDITOR'} ) {
        print indent(2) . style( "warn", "EDITOR not set, defaulting to “$default_editor” …" ) . "\n";
        $ENV{'EDITOR'} = $default_editor;
    }

    my @formatted_info_arr = map {
        my $copy = $_;    # copy so we don’t modify @info_arr
        chomp($copy);
        $copy =~ s/\n/\n# /g;
        "# $copy\n"
    } @info_arr;

    my $fh = File::Temp->new();
    print {$fh} get_editor_help_text( [ $current, "\n\n", @formatted_info_arr ] );
    close $fh;

    my $path = $fh->filename;
    system( $ENV{'EDITOR'}, "+4", $path ) && do {
        print indent(2) . style( "warn", "EDITOR failed (does not exist or is an alias?) falling back to “$default_editor” …" ) . "\n";
        $ENV{'EDITOR'} = $default_editor;

        # rewrite temp file w/ correct editor instructions:
        Cpanel::Slurper::write( $path, get_editor_help_text( [ $current, "\n\n", @formatted_info_arr ] ) );

        # try the new editor:
        system( $ENV{'EDITOR'}, "+4", $path ) && die "EDITOR still fails, bailing out";
    };
    system("reset");    # some editors (looking at you vim) need this to allow the script to continue as normal under some circumstances (piping list to STDIN and processing via -)

    # Excluding comment section
    my $string = Cpanel::Slurper::read($path);
    $string =~ s{^\s*#.+?\n}{}msg;

    $string = Cpanel::StringFunc::Trim::ws_trim($string);
    $string = " $string" if $string =~ m/^…/;
    return $string;
}

sub get_editor_help_text {
    my ($chunks) = @_;
    my $edit_specific_chunk = join( '', @{$chunks} );

    $edit_specific_chunk = Cpanel::StringFunc::Trim::ws_trim($edit_specific_chunk);

    my ( $type, $bail_out, $url ) = get_editor_text( $ENV{'EDITOR'} );

    return <<"END_INFO";
# You are in the text editor “$ENV{'EDITOR'}” to edit this phrase.
# See the “HELP” section below for more information.

$edit_specific_chunk

# [HELP]
#
# Editing:
#    • To exit out of “$type”: $bail_out
#    • To learn how to use “$type”: $url
#
# Common special characters to copy-and-paste:
#    • © ® ™ “ ” ‘ ’ …
#
# Additional reference information:
#    • Localization Portal
#       https://cpanel.wiki/display/LD/Localization+Portal
#    • HTML Tags and Entities in Localization Strings
#       http://fogbugz.cpanel.net/default.asp?W1296
#    • Bracket Notation
#       https://go.cpanel.net/localedocs
END_INFO

}

sub get_editor_text {
    my ($editor) = @_;
    $editor ||= $ENV{'EDITOR'} || '';

    my $pre = qr{(?:^|[/ ])};
    my $pst = qr{(?: |)};

    my $enter   = "ENTER";
    my $esc     = "ESC";
    my $cntrl   = "CTRL+";
    my $unknown = "Sorry, I don’t know anything about “$editor”.";
    if ( $editor =~ m/${pre}(?:[gre]{1,2})?vi(?:ew|m)?$pst/ ) {

        # $esc is necessary to get back into prompt mode, no-op if you already have a prompt
        return ( "vim", "Press $esc, then type :q then press $enter.", "http://www.cheat-sheets.org/#Vim" );
    }
    elsif ( $editor =~ m/${pre}emacs$pst/ ) {
        return ( "emacs", "Type ${cntrl}x then type ${cntrl}c", "http://www.cheat-sheets.org/#Emacs" );
    }
    elsif ( $editor =~ m/${pre}(?:pico|nano)$pst/ ) {
        return ( "nano", "Type ${cntrl}x", "http://bit.ly/i7sffd" );
    }
    else {
        return ( "unknown ($editor)", $unknown, $unknown );
    }
}

sub _do_instance_prompt {
    my ( $res_hr, $args_hr ) = @_;

    my @remaining_instances = grep { $_->{'file'} eq $res_hr->{'file'} } map { $args_hr->{'instances'}->[ -$_ ] } reverse( 1 .. $args_hr->{'remaining_count'} );
    $args_hr->{'remaining_count'} = scalar(@remaining_instances);
    $args_hr->{'instances'}       = \@remaining_instances;

    my $instance = $args_hr->{'remaining_count'} == 1 ? "instance" : "instances";
    my $res      = 'Apply';

    while (1) {

        my $prompt_text = indent(2) . style( 'bold', 'New Version: ' ) . style( 'highlight', $args_hr->{'replacement_text'} ) . "\n\n";
        $prompt_text .= "Would you like to have your change applied to “$res_hr->{'file'}” line $res_hr->{'line'}, offset $res_hr->{'offset'}?";

        # -menu => array allows us to specify order, drawback is the string is returned
        $res = Cpanel::Locale::Utils::Tool::prompt_menu(
            indent() . $prompt_text,
            [
                'Apply change to this instance only. (default)',
                "Apply change to this instance and the $args_hr->{'remaining_count'} remaining $instance in this file.",    # TODO: makethis("Apply change to this instance and the remaining [ quant, _1, instance, instances ] in this file.");
                'Skip change for this instance only.',
                "Skip change for this instance and the $args_hr->{'remaining_count'} remaining $instance in this file.",    # TODO: makethis(" Skip change for this instance and the remaining [ quant, _1, instance, instances ] in this file.")
                "More Info",
            ],
            'Apply change to this instance only. (default)',
        );

        return $res unless $res =~ m/More Info/;

        print style( 'info', "More Info:" ) . "\n";
        print indent(2) . style( 'bold', 'Initial Phrase: ' ) . style( 'highlight', $args_hr->{'phrase'} ) . "\n";
        print indent(2) . style( 'bold', 'Updated Phrase: ' ) . style( 'highlight', $args_hr->{'replacement_text'} ) . "\n";

        print indent(2) . style( 'bold', 'Remaining Instances:' ) . "\n";
        if ( $args_hr->{'remaining_count'} == 0 ) {
            print indent(3) . "There are no instances remaining.\n";
        }
        else {
            for my $res_hr (@remaining_instances) {
                print indent(3) . "$res_hr->{'file'} line $res_hr->{'line'} offset $res_hr->{'offset'}\n";
            }
        }

        print "\n";
    }

    return $res;    # not sure how it could get here but just in case. also it gives an explicit return which is good
}

sub _permanently_skip_phrase {
    my ($phrase) = @_;
    Cpanel::Encoder::utf8::encode( my $utf8_encoded_phrase = $phrase );
    my $skipped_phrases = {};
    if ( -f _skipped_phrases_file() ) {
        $skipped_phrases = Cpanel::SafeStorable::retrieve( _skipped_phrases_file() );
    }
    $skipped_phrases->{$utf8_encoded_phrase} = 1;
    Cpanel::SafeStorable::nstore( $skipped_phrases, _skipped_phrases_file() );
    print style( "info", q{The system will not ask you about that phrase again.} ) . "\n";
    return;
}

sub _skipped_phrases_file {
    my $homedir = Cpanel::PwCache::gethomedir() || die "The system could not determine your home directory.";
    return "$homedir/.locale_tool_skipped_phrases";
}

1;
