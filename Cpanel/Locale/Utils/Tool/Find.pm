package Cpanel::Locale::Utils::Tool::Find;

# cpanel - Cpanel/Locale/Utils/Tool/Find.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Text::Extract::MaketextCallPhrases 0.91               ();
use Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel ();
use Path::Iter                                            ();
use Text::Fold                                            ();
use Cwd                                                   ();

use Cpanel::Locale::Utils::Tool;    # indent(), style()
use Cpanel::Locale::Utils::Queue ();
use Cpanel::Locale::Utils::TPDS  ();

sub subcmd {
    my ( $app, $resource, @args ) = @_;

    if ( $resource eq '-' ) {
        print "Processing files provided via STDIN …\n";
        $resource = [<STDIN>];
        chomp( @{$resource} );
    }

    my %flags;
    @flags{qw(all deviants verbose extra-filters passed warnings violations no-git-check parse-tpds)} = ();
    for my $flag (@args) {
        my $dashless = $flag;
        $dashless =~ s/^--//;
        die "'find' does not know about '$flag'" if !exists $flags{$dashless};
    }

    my $opts = {};
    for my $bool ( keys %flags ) {
        $opts->{$bool} = grep( /^--$bool$/, @args ) ? 1 : 0;
    }

    # if none were given then do them them all
    if ( !$opts->{'passed'} && !$opts->{'warnings'} && !$opts->{'violations'} ) {
        $opts->{'passed'}     = 1;
        $opts->{'warnings'}   = 1;
        $opts->{'violations'} = 1;
    }

    Cpanel::Locale::Utils::Tool::Find::run( $resource, $opts );
    return;
}

sub skip_file {    # also used by cplint
    my ($f) = @_;

    return 1 unless defined $f;

    # update here update in cplint locale check (look for 'PBI 5096 will make this better')
    return 1 if $f =~ m{(?:^|/)(?:.+\.versions|tmp)$};
    return 1 if $f =~ m{^tmp/};

    return 1 if $f =~ m{(?:^|/)(?:Cpanel/CPAN|base/cldr|t|3rdparty|lang|locale|logs?|cache|\.svn|\.git)/};

    # update here update in cplint locale check (look for 'PBI 5096 will make this better')
    return 1 if $f =~ m{(?:^|/)(?:[^/]+(?:\.t|\.pod|\.diff|\.patch|\.spec\.[tj]s)|diff|Makefile)$};

    return;
}

sub run {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $resource, $opts ) = @_;
    $resource ||= '.';

    if ( -f $resource ) {

        if ( skip_file($resource) ) {
            print "The resource '$resource' is ignored.\n";
            return;
        }

        my %hash = _process_file( $resource, $opts );
        return %hash if $opts->{'return_hash'};

        if ( $opts->{'deviants'} ) {
            _process_deviant_hash( \%hash, $opts );
        }
        else {
            _process_phrase_hash( \%hash, $opts );
        }
    }
    elsif ( -d _ ) {
        my $start = time;
        my %phrases;
        my @errors;
        my $fetch = Path::Iter::get_iterator(
            $resource,
            {
                'errors'          => \@errors,
                'readdir_handler' => sub {
                    my ( $working_path, @contents ) = @_;

                    # PBI 5096 will make this better:
                    if ( $working_path ne $resource && "$working_path/" ne $resource ) {
                        return if skip_file($working_path);
                    }

                    return unless $opts->{'no-git-check'} || _is_path_in_repo($working_path);
                    return @contents;
                }
            }
        );

        my $processed_count = 0;
        my $file;    # buffer

        my $be_verbose = $opts->{'verbose'} && ( $opts->{'verbose_with_return_hash'} || !$opts->{'return_hash'} ) ? 1 : 0;
        while ( defined( $file = $fetch->() ) ) {

            # TODO: ? next if -p $file; # apparently needs done before lstat() thus we can't -p _ below
            next if -l $file || -d _ || -B _;
            next unless $opts->{'no-git-check'} || _is_path_in_repo($file);

            print "Processing “$file” …\n";
            $processed_count++;

            local $opts->{'return_hash'} = 1;
            my $started_file = time;
            my %file_phrases = _process_file( $file, $opts );

            # TODO: makethis("It took [quant,_1,second,seconds,under a second] to process “[_2]”.", time - $started_file, $file)
            my $duration = time - $started_file;
            print indent() . "seconds: $duration\n" if $be_verbose && $duration;

            # merge %file_phrases into %phrases
            for my $phrase ( keys %file_phrases ) {
                push @{ $phrases{$phrase} }, @{ $file_phrases{$phrase} };
            }
        }

        if ($be_verbose) {
            my $elapsed = time() - $start;

            # TODO: makethis("We processed [quant,_1,file,files] in [quant,_2,minute,minutes].", $processed_count, $elapsed/60);
            print "Files: $processed_count\nSeconds: $elapsed\n";
        }

        return %phrases if $opts->{'return_hash'};

        if ( $opts->{'deviants'} ) {
            _process_deviant_hash( \%phrases, $opts );
        }
        else {
            _process_phrase_hash( \%phrases, $opts );
        }
    }
    elsif ( ref($resource) eq 'ARRAY' ) {
        my %phrases;
        my $processed_count = 0;
        my $be_verbose      = $opts->{'verbose'} && ( $opts->{'verbose_with_return_hash'} || !$opts->{'return_hash'} ) ? 1 : 0;

        my %seen;
        for my $file ( @{$resource} ) {
            next if !defined $file;
            $file =~ s/^\s+//;
            $file =~ s/\s+$//;
            next if $file eq '';
            next if $seen{$file}++;
            next if -l $file || !-e _ || -d _ || -B _;    # also filter by existence (w/ dir we know it exists) no need to factor in no-git-check, assume the list is what they want regardless of if its in git or not
            print "Processing “$file” …\n";
            $processed_count++;

            local $opts->{'return_hash'} = 1;
            my $started_file = time;
            my %file_phrases = _process_file( $file, $opts );

            # TODO: makethis("It took [quant,_1,second,seconds,under a second] to process “[_2]”.", time - $started_file, $file)
            my $duration = time - $started_file;
            print indent() . "seconds: $duration\n" if $be_verbose && $duration;

            # merge %file_phrases into %phrases
            for my $phrase ( keys %file_phrases ) {
                push @{ $phrases{$phrase} }, @{ $file_phrases{$phrase} };
            }
        }

        return %phrases if $opts->{'return_hash'};

        if ( $opts->{'deviants'} ) {
            _process_deviant_hash( \%phrases, $opts );
        }
        else {
            _process_phrase_hash( \%phrases, $opts );
        }
    }
    else {
        print "Sorry, I do not know how to handle that sort of resource.\n";
        return;
    }
    return;
}

sub _process_file {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $resource, $opts ) = @_;

    my %found;
    my $norm = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel->new_source( { 'run_extra_filters' => $opts->{'extra-filters'} } ) || die "Could not create normalization object";
    my $results_ar;

    my $abs_resource = Cwd::abs_path($resource);
    if ( !$opts->{'parse-tpds'} && $abs_resource =~ m{(:?^|/)build-tools/translations/} ) {
        if ( !-x $resource ) {

            # the Cpanel::Locale::Utils::TPDS function below will warn() and ignore too but we want to make it match the rest of the tool so we capture it here
            print style( 'warn', "$resource is not executable" ) . "\n";
        }
        else {
            Cpanel::Locale::Utils::TPDS::handle_phrases_from_script_output(
                $abs_resource,    # if we use $resource and we are in build-tools/translations then `script_name` will fail (command not found)
                sub {
                    my ( $phrase, $linenum, $extra ) = @_;
                    if ( !$extra->{'file'} || !$extra->{'line'} ) {
                        $extra->{'file'} = "Output of $resource";
                        $extra->{'line'} = $linenum;
                    }
                    push @{$results_ar}, { 'phrase' => $phrase, 'original_text' => $phrase, %$extra, 'cpanel:tpds' => 1 };
                }
            );
        }
    }
    else {
        $results_ar = Text::Extract::MaketextCallPhrases::get_phrases_in_file(
            $resource,
            {
                'cpanel_mode' => 1,    # any new tokens we need to parse for need added to the upstream module’s cpanel_mode in order to keep all consumers cpanel or not consistent and universal
            }
        );
    }

    for my $result_hr ( @{$results_ar} ) {
        if ( exists $result_hr->{'phrase'} && defined $result_hr->{'phrase'} && ( !exists $result_hr->{'type'} || !defined $result_hr->{'type'} ) ) {
            next if $opts->{'deviants'};

            $result_hr->{'cpanel:location'} = Cpanel::Locale::Utils::Queue::get_location_of_key( 'en', $result_hr->{'phrase'} );
            if ( !$opts->{'all'} ) {
                next if $result_hr->{'cpanel:location'} eq 'lexicon' || $result_hr->{'cpanel:location'} eq 'queue' || $result_hr->{'cpanel:location'} eq 'human' || $result_hr->{'cpanel:location'} eq 'machine';
            }

            $result_hr->{'file'} = $resource if !exists $result_hr->{'file'};

            # if this is the first instance, include the checker info for use later when walking the results
            if ( !exists $found{ $result_hr->{'phrase'} } ) {
                $result_hr->{'cpanel:checker:result'} = $norm->normalize( $result_hr->{'phrase'} );

                $result_hr->{'cpanel:checker:style'} = 'good';
                $result_hr->{'cpanel:checker:label'} = 'Passed';

                if ( $result_hr->{'cpanel:checker:result'}->get_violation_count() ) {
                    next unless $opts->{'violations'};
                    $result_hr->{'cpanel:checker:style'} = 'error';
                    $result_hr->{'cpanel:checker:label'} = 'Failed';

                }
                elsif ( $result_hr->{'cpanel:checker:result'}->get_warning_count() ) {
                    next unless $opts->{'warnings'};
                    $result_hr->{'cpanel:checker:style'} = 'warn';
                    $result_hr->{'cpanel:checker:label'} = 'Has Warnings';
                }
                else {
                    next unless $opts->{'passed'};
                }
            }

            push @{ $found{ $result_hr->{'phrase'} } }, $result_hr;
        }
        else {
            next unless $opts->{'deviants'};
            $result_hr->{'file'} = $resource if !exists $result_hr->{'file'};
            $result_hr->{'phrase'} //= "\xe2\x90\x80";    # \x{2400} SYMBOL FOR NULL
            push @{ $found{ $result_hr->{'phrase'} } }, $result_hr;
        }
    }

    return %found;
}

sub _process_deviant_hash {
    my ($hr) = @_;

    return Cpanel::Locale::Utils::Tool::walk_hash(
        $hr,
        sub {
            my ( $phrase, $instances ) = @_;

            my ( $style, $status ) = ( "info", "normal" );
            if ( $instances->[0]{'is_error'} ) {
                ( $style, $status ) = ( "error", "Error" );
            }
            elsif ( $instances->[0]{'is_warning'} ) {
                ( $style, $status ) = ( "warn", "Warning" );
            }

            print indent() . "Type: $instances->[0]{'type'}\n";
            print indent() . "Status:  " . style( $style, $status ) . "\n";
            print indent() . "Location:\n";
            for my $res_hr ( @{$instances} ) {
                print indent(2) . "$res_hr->{'file'} line $res_hr->{'line'} offset $res_hr->{'offset'}\n";
            }
        }
    );
}

sub _process_phrase_hash {
    my ( $hr, $opts ) = @_;

    my $counts = Cpanel::Locale::Utils::Tool::get_counts_hr();

    # Processing through each phrase
    Cpanel::Locale::Utils::Tool::walk_hash(
        $hr,
        sub {
            my ( $phrase, $instances ) = @_;
            $counts->{'total'}++;
            $counts->{ $instances->[0]{'cpanel:checker:style'} }++;
            return Cpanel::Locale::Utils::Tool::Find::walk_hash_output( $phrase, $instances, $opts );
        },
        0
    );

    return Cpanel::Locale::Utils::Tool::display_counts_hr_summary($counts);
}

sub walk_hash_output {
    my ( $phrase, $instances, $opts ) = @_;

    my $status = $instances->[0]{'cpanel:location'};

    if ( $status eq 'lexicon' ) {
        $status = "In official lexicon";
    }
    elsif ( $status eq 'queue' ) {
        $status = "Queued for translation";
    }
    elsif ( $status eq 'human' ) {
        $status = "Has human translation";
    }
    elsif ( $status eq 'machine' ) {
        $status = "Has machine translation";
    }
    else {
        $status = "New (not in main cPanel repo)";
    }

    Cpanel::Locale::Utils::Tool::session_sanity_check() if $opts->{'do_session_sanity_check'};

    my $do_array = exists $opts->{'phrase_info'} && ref( $opts->{'phrase_info'} ) eq 'ARRAY' ? 1 : 0;

    if ($do_array) {

        # Exclude style formatting to avoid unexpected characters like
        # color formatting codes being included in the text editor.
        push( @{ $opts->{'phrase_info'} }, indent() . "Phrase : " . qq('$instances->[0]{'phrase'}') . "\n" );
        push( @{ $opts->{'phrase_info'} }, indent() . "Status : " . qq('$status') . "\n" );
        push( @{ $opts->{'phrase_info'} }, indent() . "Checker: " . qq('$instances->[0]{'cpanel:checker:label'}') . "\n" );
    }

    print indent() . "Status:  " . style( "info",                                  $status ) . "\n";
    print indent() . "Checker: " . style( $instances->[0]{'cpanel:checker:style'}, $instances->[0]{'cpanel:checker:label'} ) . "\n";
    if ($do_array) {
        push( @{ $opts->{'phrase_info'} }, _walk_filter( $instances->[0]{'cpanel:checker:result'}, 0, 2, $opts ) );
        push( @{ $opts->{'phrase_info'} }, _walk_filter( $instances->[0]{'cpanel:checker:result'}, 1, 2, $opts ) );
    }
    else {
        _walk_filter( $instances->[0]{'cpanel:checker:result'}, 0, 2, $opts );
        _walk_filter( $instances->[0]{'cpanel:checker:result'}, 1, 2, $opts );
    }

    print indent() . "Location:\n";
    push( @{ $opts->{'phrase_info'} }, indent() . "Location:\n" ) if $do_array;

    my $tpds_instance_count = 0;
    for my $res_hr ( @{$instances} ) {
        if ($do_array) {
            push( @{ $opts->{'phrase_info'} }, indent(2) . "$res_hr->{'file'}: line $res_hr->{'line'}, offset $res_hr->{'offset'}\n" );
        }

        print indent(2) . "$res_hr->{'file'} line $res_hr->{'line'} offset $res_hr->{'offset'}\n";
        $tpds_instance_count++ if $res_hr->{'cpanel:tpds'};
    }

    return $tpds_instance_count;
}

sub _walk_filter {
    my ( $result, $do_violations, $indent, $opts ) = @_;
    $indent ||= 1;    # to avoid uninit warnings in additions below

    my @info_arr = ();

    my ( $count_meth, $get_items, $style, $label ) = ( 'get_warning_count', 'get_warnings', 'warn', 'Warnings' );
    if ($do_violations) {
        ( $count_meth, $get_items, $style, $label ) = ( 'get_violation_count', 'get_violations', 'error', 'Violations' );
    }

    my $overall_count = $result->$count_meth();
    if ($overall_count) {

        push @info_arr, indent($indent) . "$label ($overall_count)\n";
        print indent($indent) . style( $style, $label ) . " ($overall_count)\n";

        my $output = '';
        my $number = 0;
        for my $filter_result ( @{ $result->get_filter_results() } ) {
            next if !$filter_result->$count_meth();
            for my $message ( @{ $filter_result->$get_items() } ) {
                $number++;
                $output = indent( $indent + 1 ) . Text::Fold::fold_text( "$number. $message", undef, { 'join' => "\n" . indent( $indent + 2 ), soft_hyphen_threshold => 0E0 } ) . "\n";
                push @info_arr, map { "$_\n" } split( /\n/, $output );    # turn newly folded line into multiple lines
                print $output;
            }
            if ( $opts->{'verbose'} ) {

                # Exclude style info to prevent unexpect characters when viewing in text editor
                push( @info_arr, indent( $indent + 3 ) . "More Info:" . " https://metacpan.org/pod/" . $filter_result->get_package() );

                print indent( $indent + 3 ) . style( "info", "More Info:" ) . " https://metacpan.org/pod/" . $filter_result->get_package() . "\n\n";
            }
        }
    }

    # Need to have an explicit return and avoid having '0' as the possible return value.
    return @info_arr;
}

sub get_help_text {
    return <<'END_HELP';
Find phrases in a given resource.

Phrase Mode: unknown phrases

  --all            Include known phrases in addition to unknown phrases
  --verbose        Include additional information
  --extra-filters  Enable the phrase checker’s extra filters

                   To find out more about cPanel’s phrase checker filters,
                   see the POD for Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel.

  --no-git-check   If the given resource is a directory include all files in
                   the iteration even if they are outside of the repository.

  --parse-tpds     Instead of executing the Translatable Phrase Dumper Scripts
                   and parsing their output, parse their source code instead.

  By default the following flags are all in effect unless one or more are passed in:

  --passed      Show phrases that passed the phrase checker with no warnings
  --warnings    Show phrases that passed the phrase checker with warnings
  --violations  Show phrases that failed the phrase checker

Deviant Mode: non-phrases that need attention

  --deviants  Provide details about any ambiguous localization calls

Any “Phrase Mode” flags passed in are completely ignored in “Deviant Mode”.
END_HELP
}

my $repo_files;

sub _clear_file_cache {
    undef $repo_files;
    return;
}

sub _init_file_cache {
    $repo_files = { '.' => 1 };
    foreach my $file ( split( /\n/, `git ls-files` ) ) {
        $repo_files->{$file} = 1;
        if ( $file =~ tr{/}{} ) {
            my @path = split( m{/}, $file );
            while ( defined pop(@path) && scalar @path ) {
                $repo_files->{ join( '/', @path ) }       = 1;
                $repo_files->{ join( '/', @path ) . '/' } = 1;
            }
        }
    }
    return;
}

sub _is_path_in_repo {
    my $path = shift;
    _init_file_cache() unless defined $repo_files;
    return $repo_files->{$path} ? 1 : 0;
}

1;
