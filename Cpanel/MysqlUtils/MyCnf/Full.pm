package Cpanel::MysqlUtils::MyCnf::Full;

# cpanel - Cpanel/MysqlUtils/MyCnf/Full.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use Cpanel::ConfigFiles ();
use Cpanel::LoadFile    ();
#
# Parse the my.cnf file while preserving the line order & comments
# Here we'll return an array of info on each line containing the original line
# plus any relevant section/key/value info as well
# This is useful if you want to re-write the my.cnf file after making a couple
# of changes while preserving the rest of the file in its original form
# The parsing portion of this code was taken from etc_my_cnf()
#
sub etc_my_cnf_preserve_lines {
    my ( $my_cnf, $contents ) = @_;

    $my_cnf   ||= $Cpanel::ConfigFiles::MYSQL_CNF;
    $contents ||= Cpanel::LoadFile::loadfile($my_cnf);

    return if !length $contents;    # preserve previous behavior

    my @results = ();

    # Open our my.cnf file for reading
    if ( !$contents ) {
        my $logger = Cpanel::Logger->new();
        $logger->info("Could not open the mysql config file: $my_cnf; $!");
        return;
    }

    # Loop through the my.cnf file line for line
    # For each line, save a "line item" containing
    # the original line, plus its section, key, & value where applicable
    my $section = '';
    foreach my $line ( split( m{^}, $contents ) ) {

        # Save each line, as-is, into the line item
        # If no changes are needed the line can be preserved exactly as it is
        my $line_item = { 'line' => $line };
        push @results, $line_item;

        next if $line =~ tr/;#// && $line =~ /^[ \t]*[#;]/;

        # Look at the line to determine the following:
        #  Does it start a new section?
        #  If it is within a section, we want to try
        #  to parse out the key and value
        # The code that modifies the my.cnf file will determine
        # what to modify in a line based on the section, key, & value
        my ( $key, $value );

        # Prepare the line in order to parse out key/value or section info
        # (We've already saved off the line in its original form)
        # TODO: w/ quoted values: optionally enclose the value within single quotation marks or double quotation marks, which is useful if the value contains a “#” comment character.
        $line_item->{'eol_comment'} = $1 if index( $line, '#' ) > -1 && $line =~ s{([ \t]*(?<!\\)#.*)}{};    # Save the end of line comment, so we can put it back if need be
        $line =~ s{(?:^[ \t]*|[ \t]*$)}{}g if $line =~ tr{ \t}{};                                            # better than chomp
        next if $line =~ m/^$/;                                                                              # Empty line contains newline because not chomped

        if ( index( $line, ']' ) > -1 && $line =~ m/^\[(.*?)\]/ ) {

            # New section, update the section value
            $section = $1;
        }
        elsif ( index( $line, '=' ) > -1 ) {
            if ( $line =~ m/(\S+?)[ \t]*=[ \t]*(["'])(.*?)\2/ ) {

                # Got a key/value
                $key   = $1;
                $value = $3;
                $value = '' if !defined $value;
            }
            elsif ( $line =~ m/(\S+?)[ \t]*=[ \t]*(\S+)/ ) {

                # Got a key/value
                $key   = $1;
                $value = $2;
                $value = '' if !defined $value;
            }
            elsif ( $line =~ m/^[ \t]*(\S+)[ \t]*=[ \t]*$/ ) {

                # key but no value
                $key   = $1;
                $value = '';
            }
        }
        elsif ( $line =~ m/^[ \t]*(\S+)[ \t]*$/ ) {

            # key but no value
            $key   = $1;
            $value = '';
        }

        # Add any section/key/value info we found to the line item
        $line_item->{'section'} = $section;
        $line_item->{'key'}     = $key;
        $line_item->{'value'}   = $value;
    }

    return \@results;
}

#
# Parse the my.cnf file into a tree structure:
# section -> { key -> value}
# This is useful if you want the data contianed in the my.cnf file
# and are not concerned with rewriting it, as this loses the comments
# as well as the line ordering information.
# The parsing regular expressions are duplicated in etc_my_cnf_preserve_lines() above.
# So, any changes to the parsing may need to be applied to both functions
#
sub etc_my_cnf {
    my ( $my_cnf, $contents ) = @_;

    $my_cnf   ||= $Cpanel::ConfigFiles::MYSQL_CNF;
    $contents ||= Cpanel::LoadFile::loadfile($my_cnf);

    return if !length $contents;    # preserve previous behavior

    my $stash   = {};
    my $section = '';
    foreach my $line ( split( m{^}, $contents ) ) {

        next if $line =~ tr/#;// && $line =~ /^[ \t]*[#;]/;

        # TODO: w/ quoted values: optionally enclose the value within single quotation marks or double quotation marks, which is useful if the value contains a “#” comment character.
        $line =~ s{[ \t]*(?<!\\)\#.*}{} if index( $line, '#' ) > -1;    # strip end of line comments (if \# is not a valid way to incldue a literal # then the look behind can be dropped)
        $line =~ s{(?:^[ \t]*|[ \t]*$)}{}g if $line =~ tr{ \t}{};       # better than chomp
        next if $line eq '';

        if ( index( $line, ']' ) > -1 && $line =~ m/^\[(.*?)\]/ ) {
            $section = $1;
        }
        elsif ( index( $line, '=' ) > -1 ) {
            if ( $line =~ m/(\S+?)[ \t]*=[ \t]*(["'])(.*?)\2/ ) {
                $stash->{$section}{$1} = $3;
            }
            elsif ( $line =~ m/(\S+?)[ \t]*=[ \t]*(\S+)/ ) {
                $stash->{$section}{$1} = $2;

                # TODO: escape sequences “\b”, “\t”, “\n”, “\r”, “\\”, and “\s” in option values
                #       ? escape sequences in group names or option keys ?
            }
            elsif ( $line =~ m/^[ \t]*(\S+)[ \t]*=[ \t]*$/ ) {
                $stash->{$section}{$1} = '';
            }
        }
        elsif ( $line =~ m/^[ \t]*(\S+)[ \t]*$/ ) {
            $stash->{$section}{$1} = undef;    # ? or should this be '1' ?
        }
    }

    # since this is fatal we should never get here, if we do then it needs addressed
    # error: Found option without preceding group in config file: /etc/my.cnf at line
    if ( exists $stash->{''} ) {
        require Cpanel::Logger;
        my $logger = Cpanel::Logger->new();
        $logger->info("error: Found option without preceding group in config file: $my_cnf");

        # If a manual edit left out a group label they most likley meant mysqld
        # If they have a mysqld group then they must have meant it for another group and it is impossible to guess (which is my mysql just dies when it sees this)
        if ( !exists $stash->{'mysqld'} ) {
            $logger->info("Assigning 'options without preceding group' to non-existant 'mysqld' group");
            $stash->{'mysqld'} = $stash->{''};
        }
    }

    return $stash;

}

1;
