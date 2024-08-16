package Cpanel::Logger::Serialized;

# cpanel - Cpanel/Logger/Serialized.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Autodie              ();
use Cpanel::Exception            ();
use Cpanel::FileUtils::Open      ();
use Cpanel::FileUtils::Read      ();
use Cpanel::AdminBin::Serializer ();

use Try::Tiny;

#Accepts parameters:
#
#   log_file    the full path to the log file
#
sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'log_file' ] ) if !$OPTS{'log_file'};
    my $log_file = $OPTS{'log_file'};

    my $self = bless {
        'log_file' => $log_file,
    }, $class;

    return $self;
}

###########################################################################
#
# Method:
#   serialize_entry_to_log
#
# Description:
#   This method opens a file serializes a data structure into JSON format, then
#   appends the JSON text as a line to the file. This method ONLY accepts references.
#   NOTE: Currently, this method opens and closes the log with each write.
#
# Parameters:
#   log_entry - The data structure/reference that is meant to be serialized to the log file.
#               This entry will be converted to JSON format and then appended to the log.
#
# Exceptions (assume these start with Cpanel::Exception:: unless otherwise noted):
#   InvalidParameter  - Thrown if the 'log_entry' parameter is not a reference.
#   IO::FileOpenError - Thrown if there is an error in opening the log file.
#
#   Exceptions thrown by Cpanel::Autodie, including the following:
#       IO::WriteError     - Thrown if there is an error in writing to the log file.
#       IO::FileCloseError - Thrown if there is an error in closing the log file.
#
# Returns:
#   This method always returns 1 or throws an exception.
#
sub serialize_entry_to_log {
    my ( $self, $log_entry ) = @_;

    my $log_file = $self->{'log_file'};

    if ( !ref $log_entry ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be a reference.', ['log_entry'] );
    }

    my $fh;

    #TODO: Consider putting this functionality into Cpanel::Autodie::Easy (::More in 11.52+)
    if ( !Cpanel::FileUtils::Open::sysopen_with_real_perms( $fh, $log_file, 'O_WRONLY|O_APPEND|O_CREAT', 0640 ) ) {

        #NOTE: The exception object doesn't parse the pipe-delimited strings as
        #sysopen_with_real_perms() does.
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $log_file, mode => '>>', error => $!, permissions => '0640' ] );
    }

    my $serialized_entry = Cpanel::AdminBin::Serializer::SafeDump($log_entry);

    Cpanel::Autodie::print( $fh, "$serialized_entry\n" );

    Cpanel::Autodie::close($fh);

    return 1;
}

###########################################################################
#
# Method:
#   deserialize_entries_from_log
#
# Description:
#   This method opens a file and deseralizes data structures from it, one entry per line. It allows for
#   a coderef to be passed in to reformat or handle the processing of each of these entries.
#
# Parameters:
#   data_transform_cr => This method expects a code reference that handles the processing
#                        of each entry in the log file. The code ref should expect to receive
#                        one reference as its only parameter. The reference is the deserialized
#                        data structure from the log file.
#                        It is expected that this coderef should also populate an external data structure during
#                        the processing of the log entry; therefore, this method always returns 1.
#
#   error_handler_cr  => This method also expects a code reference as its second parameter that
#                        handles any errors while deserializing the JSON string. It should expect
#                        two parameters. The first being the text of the line that failed, and the
#                        second being the parse error thrown by JSON.
#
# Exceptions (assume these start with Cpanel::Exception:: unless otherwise noted):
#   In addition to any exceptions the 'data_transform_cr' may throw, this method may also throw the
#   following exceptions.
#
#   Also whatever exceptions Cpanel::FileUtils::Read::for_each_line may throw. Currently at time of writing:
#       IO::FileOpenError  - Thrown if there is an error in opening the log file.
#       IO::FileReadError  - Thrown if there is an error in reading the log file.
#       IO::FileCloseError - Thrown if there is an error in closing the log file.
#
# Returns:
#   This method always returns 1. Extraction of data from the entries in the log is to be done
#   via the 'data_transform_cr'.
#
sub deserialize_entries_from_log {
    my ( $self, $data_transform_cr, $error_handler_cr ) = @_;

    my $log_file = $self->{'log_file'};

    Cpanel::FileUtils::Read::for_each_line(
        $log_file,
        sub {
            my $line = $_;

            chomp($line);

            my ( $entry_ref, $error );
            try {
                $entry_ref = Cpanel::AdminBin::Serializer::Load($line);
            }
            catch {
                $error = $_;
            };

            if ($error) {
                $error_handler_cr->( $line, $error );
            }
            else {
                $data_transform_cr->($entry_ref);
            }
        }
    );

    return 1;
}

1;
