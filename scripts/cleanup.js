var AWS = require('aws-sdk');
var moment = require('moment');
var queue = require('d3-queue').queue;
var request = require('request');
var _ = require('underscore');

var user = process.argv[2];
var repo = process.argv[3];
var GithubAccessToken = process.env.GithubAccessToken;

var ecr = new AWS.ECR();
var params = {
  repositoryName: repo
};

ecr.listImages(params, function (err, data) {
  if (err) console.log(err, err.stack);
  var results = data.imageIds;

  var q = queue(10);
  for (var i = 0; i < results.length; i++) {
    var commit = results[i].imageTag;
    if (commit === undefined) {
      console.log('Image digest '+ results[i].imageDigest + ' did not have an image tag.');
    } else {
      var options = {
        url: 'https://api.github.com/repos/' + user + '/' + repo + '/commits/' + commit + '?access_token=' + GithubAccessToken,
        headers: { 'User-agent': 'request' }
      };
      q.defer(request, options);
    }
  }

  q.awaitAll(function (error, response) {
    if (error) throw new Error(error);
    var results = [];
    for (var i = 0; i < response.length; i++) {
      if (response[i].statusCode !== 200) {
        var commit = response[i].request.uri.pathname.match(/\/([a-z0-9]*)$/)[1];
        console.log('Image tag ' + commit + ' could not be retrieved from GitHub.');
      } else {
        var result = JSON.parse(response[i].body);
        var object = {
          imageTag: result.sha,
          date: moment(result.commit.author.date).unix()
        };
        results.push(object);
      }
    };
    var sorted = _.sortBy(results, function(o) { return o.date; });
    console.log(sorted);
  })
})
