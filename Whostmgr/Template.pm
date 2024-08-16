package Whostmgr::Template;

# cpanel - Whostmgr/Template.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Template - legacy WHM templates

=head1 SYNOPSIS

    print Whostmgr::Template::process( {
        file => ...,    #relative to $ULC/whostmgr/templates
        ...,
    } );

=head1 DESCRIPTION

This legacy template system is B<DEPRECATED> with extreme prejudice. Please
do not use it in new code. Consider migrating any templates to use the standard
L<Cpanel::Template> templates.

This documentation is here to help those who may need to maintain the few
usages we have left of this old system.

=head1 TEMPLATE SYNTAX

Here’s at least a partial summary of what you can do with this. (The
documentation here WAAY postdates the code!)

=head2 Show/Hide

    #This must be at the start of a line
    !somekey=somevalue!
    ...
    !somekey!

This will check the hash passed to C<process()> for a key named
C<settings-somekey> and, if that value is C<somevalue>, show the
section. Otherwise, the section is not printed.

=head2 Substitution

    %somekey%

This will substitute in the value of C<somekey> as passed in the
hash reference given to C<process()>.

=head2 Looping

    #This must be at the start of a line
    !@things@!
        Hello, %name% (%nickname%).
    !@things@!

This will iterate through C<@things> in the hash passed to C<process()>.
It expects those items to be hash references; within those hash references,
it will substitute in the values of the C<name> and C<nickname> entries.

=head2 MagicRevision

    %MagicRevision:/url/to/resource%

This will output the result of
C<Cpanel::MagicRevision::calculate_magic_url('/url/to/resource')>.

=cut

use strict;

use Cpanel::MagicRevision     ();
use Cpanel::StringFunc::Match ();
use Whostmgr::Theme           ();

##################################################
# Substitute multiple values according to hash ref. (See
# process)
##################################################
sub _substitute_multiple_values {
    my ( $input_text_block, $sub_array_ref, $print ) = @_;

    if ( !defined($input_text_block) || $input_text_block eq '' ) {
        return '';
    }

    # check if this key exists at all
    if ( !defined($sub_array_ref) ) {
        return '';
    }

    # is our arg_ref not a array ref?
    if ( ref $sub_array_ref ne 'ARRAY' ) {
        return '';
    }

    my $return_block = '';
    foreach my $substitution ( @{$sub_array_ref} ) {
        $return_block .= _substitute_values( $input_text_block, $substitution, $print );
    }
    return $return_block;
}

##################################################
# Substitute values according to hash ref. (See
# process)
##################################################
sub _substitute_values {
    my ( $line, $arg_ref, $print ) = @_;

    my $output;
    if ( index( $line, '%' ) == -1 ) {
        if   ($print) { print $line; }
        else          { return $line; }
        return $output;
    }

    # regular substitutions should be inserted into %% templates..
    if ( ref $arg_ref eq '' && $arg_ref ne '' ) {
        $line =~ s/\%\%/$arg_ref/mg;
        if   ($print) { print $line; }
        else          { $output = $line; }
    }

    # arrays of hash references should be inserted into regular
    # %key% templates.
    else {
        my $key;
        my $startpos;
        while ( $line =~ /\%([^\s\%]+)\%/g ) {
            $key      = $1;
            $startpos = ( pos($line) - length($key) - 2 );
            if ($print) { print substr( $line, 0, $startpos ); }
            else        { $output .= substr( $line, 0, $startpos ); }
            if ( $key =~ /^MagicRevision:(.*)/ ) {
                if   ($print) { print Cpanel::MagicRevision::calculate_magic_url($1); }
                else          { $output .= Cpanel::MagicRevision::calculate_magic_url($1); }
            }
            elsif ( $key !~ /^settings-/ && defined $arg_ref->{$key} ) {
                if ( ref $arg_ref->{$key} eq 'ARRAY' ) {
                    foreach my $aline ( @{ $arg_ref->{$key} } ) {
                        if   ($print) { print $aline; }
                        else          { $output .= $aline; }
                    }
                }
                elsif ( ref $arg_ref->{$key} eq 'CODE' ) {
                    if   ($print) { print &{ $arg_ref->{$key} }(1); }
                    else          { $output .= &{ $arg_ref->{$key} }(); }
                }
                else {
                    if   ($print) { print $arg_ref->{$key}; }
                    else          { $output .= $arg_ref->{$key}; }
                }
            }
            $line = substr( $line, pos($line) );
        }
        if   ($print) { print $line; }
        else          { $output .= $line; }
    }
    return $output;
}
##################################################
# Clean unprocessed values due to non-existing keys
# (see process)
##################################################
sub _remove_unprocessed_values {
    my $line = shift;

    # Process unprocessed (missing keys)
    while ( $line =~ m/\%[^\%\s]+\%/mg ) {
        $line =~ s/\%\w*\%//mg;
    }
    return $line;
}

##################################################
# Evaluate the conditional templates (see process)
##################################################
sub _is_any_setting_matching {
    my $line    = shift;
    my $arg_ref = shift;

    my $exists_not_operator = 0;
    if ( $line =~ m/\!\=/ ) {
        $exists_not_operator = 1;
    }

    # split the line into 2 using '=' or '!='
    my ( $key, $val ) = split( m/\!?=/, $line, 2 );
    my $expected_key = 'settings-' . $key;

    if ( exists $arg_ref->{$expected_key}
        && $arg_ref->{$expected_key} ne '' ) {

        if ($exists_not_operator) {
            return $arg_ref->{$expected_key} ne $val;
        }
        else {
            return $arg_ref->{$expected_key} eq $val;
        }
    }
    return;
}

##################################################
# Process a template file and substitute according to
# the provided reference to a hash
##################################################
sub process {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    local $Cpanel::App::appname = 'whostmgr';    #make sure we get the right magic revision module

    my $arg_ref = shift;
    my $noprint = shift;
    my $print   = $noprint             ? 0 : 1;
    my $debug   = $arg_ref->{'_debug'} ? 1 : 0;
    if ( !exists $arg_ref->{'file'} ) {
        return ('Missing file argument. ');
    }

    my $need_x_fallback = 0;

    my $template_file;
    my $given_template_file = $arg_ref->{'file'};

    #process relative paths
    if ( $given_template_file !~ m{\A/} ) {
        $template_file = Whostmgr::Theme::find_file_path( 'templates/' . $given_template_file );
        if ( !$template_file ) {
            return ("Could not find template $given_template_file!");
        }
    }
    elsif ( !-e $given_template_file ) {    #absolute paths, fallback to x theme
        my $x_file = $given_template_file;
        if ( $x_file =~ m{\A/usr/local/cpanel/whostmgr/docroot/themes/[^/]+/} ) {
            $x_file =~ s{\A(/usr/local/cpanel/whostmgr/docroot/themes/)[^/]+}{$1x}g;
        }
        if ( -e $x_file ) {
            $need_x_fallback = 1;
            $template_file   = $x_file;
        }
        else {
            return ("File: $given_template_file does not exist!");
        }
    }
    else {
        $template_file = $given_template_file;
    }

    my $output;
    my $multiple_subs_block;
    my @in_if_block;
    my %in_if_registry;
    my $in_multiple_subs_block = 0;
    my $should_keep_block      = 1;

    if ( open my $template_fh, '<', $template_file ) {
      PARSER:
        while ( my $current_line = <$template_fh> ) {

            # skip comments
            next if index( $current_line, '@' ) == 0;

            # stop at the end of data
            last if index( $current_line, '__END__' ) == 0;

            # multiple substitutions !@items@! blocks
            if ( $current_line =~ m/^\!\@\@(include)\s+([^\@]+)\@\@\!/ ) {
                my $command = $1;
                my $opt     = $2;

                if ( $command eq 'include' ) {
                    if ( $opt !~ m{\A/} ) {
                        $opt = '/usr/local/cpanel/whostmgr/docroot/' . $opt;
                    }
                    $opt =~ s{/+}{/}g;
                    if ($need_x_fallback) {
                        $opt =~ s{\A(/usr/local/cpanel/whostmgr/docroot/themes/)[^/]+}{$1x}g;
                    }
                    if ( !Cpanel::StringFunc::Match::beginmatch( $opt, '/usr/local/cpanel/whostmgr/docroot/' ) ) {
                        next;
                    }
                    $arg_ref->{'file'} = $opt;
                    process( $arg_ref, $noprint );
                }
            }
            elsif ( $current_line =~ m/^\!@/ ) {

                # check if the block ends
                if ($in_multiple_subs_block) {
                    $in_multiple_subs_block = 0;

                    my $multiple_subs_key;

                    if ( $current_line =~ /^\!@([\S]+)@\!/ ) {
                        $multiple_subs_key = $1;
                    }

                    # now we need to process the block
                    $output .= _substitute_multiple_values( $multiple_subs_block, $arg_ref->{$multiple_subs_key}, $print );
                }

                # check if the block begins
                else {
                    $in_multiple_subs_block = 1;
                    $multiple_subs_block    = '';

                }
            }

            # simple substitution lines such as %name% stuff
            elsif ( $current_line !~ m/^\!/ ) {

                next PARSER if ( !$should_keep_block );

                # skip multiple substitutions blocks, we handle this in the
                # next elsif block. (We save these blocks to be processed
                # later)
                if ($in_multiple_subs_block) {
                    $multiple_subs_block .= $current_line;
                    next PARSER;
                }

                $output .= _substitute_values( $current_line, $arg_ref, $print );
            }

            # regular conditional substitution !condition=1! blocks.
            else {
                chomp($current_line);
                $current_line =~ s/^\s*\!|\!\s*$//g;
                my ( $condition, $cond_value ) = split /!?=/, $current_line, 2;

                if ($debug) {
                    my $status = $should_keep_block ? 'SHOWN' : 'HIDDEN';
                    if ( defined $cond_value ) {
                        $output .= "BEGINNING IF $current_line STATUS: $status<br />\n";
                    }
                    else {
                        $output .= "ENDING IF $current_line STATUS: $status<br />\n";
                    }
                    if (@in_if_block) {
                        $output .= 'Current nesting: ' . join( ', ', @in_if_block ) . "<br />\n";
                    }
                }

                if ( @in_if_block && $in_if_block[$#in_if_block] =~ m/^\s*\Q$current_line\E!?=/ ) {
                    pop @in_if_block;
                    if (@in_if_block) {
                        $should_keep_block = $in_if_registry{ $in_if_block[$#in_if_block] };
                    }
                    else {
                        $should_keep_block = 1;
                    }
                }
                else {
                    push @in_if_block, $current_line;
                    if ( !exists $in_if_registry{$current_line} ) {
                        $in_if_registry{$current_line} = _is_any_setting_matching( $current_line, $arg_ref );
                    }

                    if ($should_keep_block) {
                        $should_keep_block = $in_if_registry{$current_line};
                    }
                }

                if ($debug) {
                    if ( defined $cond_value ) {
                        my $cond_status = $in_if_registry{$current_line} ? 'TRUE' : 'FALSE';
                        $output .= "CONDITION RESULTS: $cond_status<br />\n";
                    }
                    if (@in_if_block) {
                        $output .= 'Current nesting: ' . join( ', ', @in_if_block ) . "<br />\n";
                    }
                    my $status = $should_keep_block ? 'SHOWN' : 'HIDDEN';
                    $output .= "Finished $current_line STATUS: $status<br /><br />\n";
                    $output .= "\n";
                }
            }
        }
        close $template_fh;
    }
    return $output;
}

1;
