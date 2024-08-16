package Cpanel::Locale::Utils::Tool::Blend;

# cpanel - Cpanel/Locale/Utils/Tool/Blend.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use File::Path::Tiny ();
use Path::Iter       ();

use Cpanel::Locale::Utils::Tool;    # indent(), style()
use Cpanel::DataStore ();

sub subcmd {
    my ( $app, $src, @args ) = @_;

    my %flags;
    @flags{qw(verbose no-git-check dryrun)} = ();
    for my $flag (@args) {
        my $dashless = $flag;
        $dashless =~ s/^--//;
        die "'find' does not know about '$flag'" if !exists $flags{$dashless};
    }

    my $opts = {};
    for my $bool ( keys %flags ) {
        $opts->{$bool} = grep( /^--$bool$/, @args ) ? 1 : 0;
    }

    my $git_check = $opts->{'no-git-check'} ? 0 : 1;

    die "No source repo/branch given\n" if !$src;

    if ( $git_check && system(qw(git diff --exit-code --quiet)) != 0 ) {
        die "Repo has unstaged changes.\n";
    }
    elsif ( $git_check && system(qw(git diff-index --cached --quiet HEAD --ignore-submodules)) != 0 ) {
        die "Repo has uncommitted changes.\n";
    }
    else {

        my $tmp_dir = "tmp/$src-locale-$$/locale/";

        # not likely but possible:
        if ( -d $tmp_dir ) {
            print "Removing existing directory “$tmp_dir” …\n";
            File::Path::Tiny::rm($tmp_dir) or die "Could not remove “$tmp_dir”: $!\n";
        }

        if ( !-d 'tmp' ) {
            File::Path::Tiny::mk('tmp') or die "Could not create tmp/: $!\n";
        }

        # array context helps make sure $src is safe and valid
        for my $cmd (
            [ qw(git archive --format tar.gz --output), "tmp/$src-locale-$$.tar.gz", "--prefix=$tmp_dir", "$src:locale/" ],
            [ qw(tar xzf), "tmp/$src-locale-$$.tar.gz" ],
        ) {

            # why not check again before each one just to be sure we are still good
            if ($git_check) {
                die "Repo has unstaged changes.\n"    if system(qw(git diff --exit-code --quiet)) != 0;
                die "Repo has uncommitted changes.\n" if system(qw(git diff-index --cached --quiet HEAD --ignore-submodules)) != 0;
            }

            my $cmd_str = join( ' ', @{$cmd} );
            print style( 'info', "Executing: $cmd_str" ) . "\n";

            system( @{$cmd} ) && die "“$cmd_str” did not exit cleanly: $?\n";
        }

        blend_locale_dir( $tmp_dir, 'locale/', $opts );

        File::Path::Tiny::rm($tmp_dir) or die "Could not remove “$tmp_dir”: $!\n";

        if ( $opts->{'dryrun'} ) {
            print style( "warn", "In dryrun mode, locale/ is unchanged" ) . "\n";
        }
        else {
            print style( 'good', "Done! locale/ should now contain the stuff in $src:locale/" ) . "\n";
        }
    }

    return;
}

sub blend_locale_dir {
    my ( $src, $trg, $opts ) = @_;

    print style( 'info', "Updating “$trg” (from $src) …" ) . "\n";

    die "“$src” is not a directory!\n" if !-d $src;
    die "“$trg” is not a directory!\n" if !-d $trg;

    $src .= '/' if $src !~ m{/$};
    $trg .= '/' if $trg !~ m{/$};

    my @err;
    my $fetch = Path::Iter::get_iterator( $src, { errors => \@err } );
    my $next_path;    # buffer
    while ( defined( $next_path = $fetch->() ) ) {
        next if -l $next_path || -d _;
        next if $next_path =~ m{/\.gitignore$};

        my $local_path = $next_path;
        $local_path =~ s{\Q$src\E}{$trg};

        if ( -l $local_path ) {
            print indent() . style( 'warn', "Skipping symlink ($local_path), what is a symlink doing in locale/?" ) . "\n" if $opts->{'dryrun'} || $opts->{'verbose'};
            next;
        }
        elsif ( !-e $local_path ) {
            print indent() . "Copying new file “$local_path” …\n" if $opts->{'dryrun'} || $opts->{'verbose'};

            my $dir = $local_path;
            $dir =~ s{[^/]+$}{};
            if ( !-d $dir ) {
                print indent(2) . "Creating missing directory “$dir” …\n" if $opts->{'dryrun'} || $opts->{'verbose'};
                next                                                      if $opts->{'dryrun'};
                File::Path::Tiny::mk($dir) or die "Could not make the directory “$dir”: $!\n";
            }

            next if $opts->{'dryrun'};

            system( "cp", "-p", $next_path, $local_path ) && die "Could not copy “$next_path” to “$local_path”: $?";
            system( "git", "add", $local_path ) && die "Could not stage “$local_path”: $?";
        }
        else {
            my $file_is_legacy = $next_path =~ m/\.yaml$/ ? 0 : 1;    # this refers to the where the data comes form, not the file’s format, its all YAML in here!

            print indent() . ( $file_is_legacy ? "(Legacy)  " : "(Lexicon) " ) . "$next_path → $local_path\n" if $opts->{'dryrun'} || $opts->{'verbose'};

            next if $opts->{'dryrun'};

            my $src_hr = Cpanel::DataStore::load_ref($next_path)  or die "Could not load “$next_path”: $!";
            my $trg_hr = Cpanel::DataStore::load_ref($local_path) or die "Could not load “$local_path”: $!";

            my $change_count = blend_lexicon_hash( $src_hr, $trg_hr, $local_path );
            print indent(2) . "Number of changes in “$local_path”: $change_count\n" if $opts->{'verbose'};

            if ($change_count) {
                Cpanel::DataStore::store_ref( $local_path, $trg_hr ) or die "Could not save “$local_path”: $!";
            }
        }
    }

    if (@err) {
        print style( 'error', 'The following errors occured (i.e. locale/ may not be completely updated):' ) . "\n";
        for my $err (@err) {
            print indent() . "$err->{'function'} on $err->{'path'} failed: $err->{'error'}\n";
            if ( $opts->{'verbose'} ) {
                my $arg_str = join( ', ', @{ $err->{'args'} } );
                print indent(1) . "$err->{'function'}( $arg_str )\n";
            }
        }
    }

    # We could handle files that have been removed from $src here, perhaps via a prompt to make it easy for the human to do the appropriate thing.

    return;
}

sub blend_lexicon_hash {
    my ( $src_hr, $trg_hr, $trg_file ) = @_;

    my $change_count = 0;

    for my $lex_key ( keys %{$src_hr} ) {
        if ( !exists $trg_hr->{$lex_key} ) {
            $trg_hr->{$lex_key} = $src_hr->{$lex_key};
            $change_count++;
        }
        else {
            if ( defined $src_hr->{$lex_key} && defined $trg_hr->{$lex_key} && $trg_hr->{$lex_key} ne $src_hr->{$lex_key} ) {
                my $phrase = style( 'highlight', $lex_key );
                my $res    = Cpanel::Locale::Utils::Tool::prompt_menu(
                    "Which version of the target phrase do you want to keep in “$trg_file”?\nSource Phrase: $phrase\n",
                    [
                        "Remote Target Phrase: $src_hr->{$lex_key}",
                        "Local Target Phrase : $trg_hr->{$lex_key}",
                    ]
                );

                if ( defined $res && $res =~ m/^Remote / ) {
                    $trg_hr->{$lex_key} = $src_hr->{$lex_key};
                    $change_count++;
                }
            }
        }
    }

    return $change_count;
}

1;
