#!/usr/bin/env perl 

###########################################################################
##
##         FILE: upload_dumpfiles.pl
##
##        USAGE: ./upload_dumpfiles.pl --error --file
##
##  DESCRIPTION: Uploads dumpfiles to Wikipedia from Checkwiki output
##
##       AUTHOR: Bgwhite
##      LICENSE: GPLv3
##      VERSION: 2014/05/24
##
###########################################################################

use strict;
use warnings;

use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

###########################################################################

our $SUMMARY  = "October 2015 dump";
our $TMPDIR   = "/data/project/checkwiki/var/lists/";
our $Username = q{};
our $Password = q{};
our @errors;
our $bot = MediaWiki::Bot->new(
    {
        assert   => 'bot',
        protocol => 'http',
        host     => 'en.wikipedia.org',
    }
);

my ( $Error_file, $Error_number );

GetOptions(
    'error=s' => \$Error_number,
    'file=s'  => \$Error_file
);

if ( !defined($Error_number) ) {
    print "No error number given\n\n";
    die "usage: program --error [NUMBER or all] --file [FILENAME]\n";
}
if ( !defined($Error_file) ) {
    print "No file name given\n\n";
    die "usage: program --error [NUMBER or all] --file [FILENAME]\n";
}

if ( $Error_number eq 'all' ) {
    @errors =
      qw ( 1 2 3 4 5 6 7 8 9 10 12 13 14 15 16 17 19 20 22 23 24 25 26 28 29 31 32 34 36 37 38 39 40 42 43 44 45 46 47 48 49 52 54 55 57 58 59 60 61 62 63 64 65 65 66 69 70 71 72 73 74 76 78 80 83 84 85 86 88 89 90 91 93 94 95 96 97 98 99 100 101 102 103 );
}
else {
    @errors = ($Error_number);
}

###########################################################################
## MAIN ROUTINE
###########################################################################

get_login_info();
login();
parse_errors();
upload_text();

$bot->logout();
print "All done\n";

###########################################################################
## LOGIN INFO
###########################################################################

sub get_login_info {

    if ( $Username eq q{} or $Password eq q{} ) {

        print "Enter username: ";
        $Username = <>;
        chomp $Username;

        print "Password for user " . $Username . " on Wikipedia:";
        system("stty -echo");
        chop( $Password = <> );
        system("stty echo");

        chomp $Password;
    }

    return ();
}

###########################################################################
## LOGIN
###########################################################################

sub login {

    print "\n\nLogging in to Wikipedia as " . $Username . "\n";

    $bot->login(
        {
            username => $Username,
            password => $Password,
        }
    ) or die "Login failed\n";

    return ();
}

###########################################################################
## PARSE ERRORS
###########################################################################

sub parse_errors {

    my @error_list;
    open( my $list_of_errors, "<:encoding(UTF-8)", $Error_file )
      or die 'Could not open file ' . $Error_file . "\n";
    while (<$list_of_errors>) {
        push( @error_list, $_ );
    }
    close($list_of_errors);

    foreach my $error (@errors) {

        print "CREATING: " . $error . "\n";
        my $filename = $error . '.txt';
        my @titles;
        foreach (@error_list) {
            my $line = $_;
            if ( $line =~ /\t$error\t([^\t]*)\t/ ) {
                push( @titles, $1 );
            }
        }

        my @sorted_titles = sort(@titles);
        open( my $outfile, ">:encoding(UTF-8)", $filename )
          or die 'Could not open file ' . $filename . "\n";
        foreach (@sorted_titles) {
            print $outfile '# [[' . $_ . "]]\n";
        }
        close($outfile);
    }

    return ();
}

###########################################################################
## UPDATE WEBPAGES
###########################################################################

sub upload_text {

    foreach my $error (@errors) {

        print "UPLOADING: " . $error . "\n";

        my $file = $error . '.txt';
        my $page;

        if ( $error < 10 ) {
            $page = 'Wikipedia:CHECKWIKI/00' . $error . '_dump';
        }
        elsif ( $error < 100 ) {
            $page = 'Wikipedia:CHECKWIKI/0' . $error . '_dump';
        }
        else {
            $page = 'Wikipedia:CHECKWIKI/' . $error . '_dump';
        }

        open( my $infile, "<:encoding(UTF-8)", $file )
          or die 'Could not open file ' . $file . "\n";
        my $text = do { local $/; <$infile> };

        $bot->edit(
            {
                page    => $page,
                text    => $text,
                summary => $SUMMARY,
            }
        );

        close($infile);
    }

    return ();
}