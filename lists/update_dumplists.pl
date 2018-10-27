#!/usr/bin/env perl

###########################################################################
##
##         FILE: update_dumplists.pl
##
##        USAGE: ./update_dumplists.pl --error
##
##  DESCRIPTION: Retrieves dumps lists from Wikipedia, scans the articles
##               and then uploads and updated lists
##
##       AUTHOR: Bgwhite
##      LICENSE: GPLv3
##      VERSION: 2014/05/24
##
###########################################################################

use strict;
use warnings;
use Encode;

use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

###########################################################################

our $SUMMARY  = "Dump recheck";
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

my ($Error_number);

GetOptions( 'error=s' => \$Error_number, );

if ( !defined($Error_number) ) {
    print "No error number given\n\n";
    die "usage: program --error [NUMBER or all]\n";
}

@errors = ($Error_number);
if ( $Error_number eq 'all' ) {
    @errors =
      qw ( 1 2 3 4 5 6 7 8 9 10 12 13 14 15  17 19 20 22 23 24 25 26 28 29 31 32 34 36 37 38 39 40 42 43 44 45 46 47 48 49 52 54 55 57 58 59 60  62 63 64 65 65 66 69 70 71 72 73 74 76 78 80 83 84 85 86 88 89 93 94 95 96 97 98 99 100 101 102 103 104 );
      #qw ( 1 2 3 4 5 6 7 8 9 10 12 13 14 15 16 17 19 20 22 23 24 25 26 28 29 31 32 34 36 37 38 39 40 42 43 44 45 46 47 48 49 52 54 55 57 58 59 60 61 62 63 64 65 65 66 69 70 71 72 73 74 76 78 80 83 84 85 86 88 89 90 91 93 94 95 96 97 98 99 100 101 102 103 104 105 );
}

###########################################################################
## MAIN ROUTINE
###########################################################################

get_login_info();
login();
get_errors();
parse_errors();

upload_text();

$bot->logout();
print "All done\n";

###########################################################################
## LOGIN
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
    ) or die "Login failed" . "\n";

    print "Should be logged in now\n";

    return ();
}

###########################################################################
## GET ERRORS
###########################################################################

sub get_errors {

    foreach my $error (@errors) {

        my $page_title;
        my $filename = $TMPDIR . $error . '.in';

        if ( $error < 10 ) {
            $page_title = 'Wikipedia:CHECKWIKI/00' . $error . '_dump';
        }
        elsif ( $error < 100 ) {
            $page_title = 'Wikipedia:CHECKWIKI/0' . $error . '_dump';
        }
        else {
            $page_title = 'Wikipedia:CHECKWIKI/' . $error . '_dump';
        }

        print 'Retrieving information from ' . $page_title . "\n";

        open( my $outfile, ">:encoding(UTF-8)", $filename )
          or die 'Cannot open temp file ' . $filename . "\n";

        my $wikitext = $bot->get_text($page_title);

        my @lines = split( /\n/, $wikitext );
        foreach (@lines) {
            $_ =~ /# \[\[(.*?)\]\]/;
            print $outfile $1 . "\n";
        }
        close($outfile);

    }
    return ();

}

##########################################################################
## PARSE ERRORS
##########################################################################

sub parse_errors {

    foreach (@errors) {

        my $error    = $_;
        my $filename = $TMPDIR . $error . '.txt';
        my $list     = $TMPDIR . $error . '.in';

        my @myarray =
`/usr/bin/perl /data/project/checkwiki/bin/checkwiki.pl --load list  --listfile=$list -c /data/project/checkwiki/checkwiki.cfg --project=enwiki`;

        print "Processing error " . $error . "\n";

        open( my $outfile, ">:encoding(UTF-8)", $filename )
          or die 'Cannot open temp file ' . $filename . "\n";

        foreach (@myarray) {
            $_ = decode_utf8($_);
            $_ =~ /\t([^\t]*)\t([^\t]*)\t/;
            if ( $error eq $1 ) {
                print $outfile '# [[' . $2 . "]]\n";
            }
        }
        close($outfile);
    }
    return ();

}

###########################################################################
## UPDATE WEBPAGES
###########################################################################

sub upload_text {

    print "Updating Wikipedia pages\n";

    foreach my $error (@errors) {

        my $file = $TMPDIR . $error . '.txt';
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
          or die 'Cannot open temp file ' . $file . "\n";

        my $text = do { local $/; <$infile> };
        close($infile);

        $bot->edit(
            {
                page    => $page,
                text    => $text,
                summary => $SUMMARY,
            }
        );

    }

    return ();
}