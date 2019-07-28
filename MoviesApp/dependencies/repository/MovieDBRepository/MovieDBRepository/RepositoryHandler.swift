//
//  RepositoryHandler.swift
//  MovieDBRepository
//
//  Created by Guillermo Gutierrez on 7/9/19.
//  Copyright © 2019 ggutierrez. All rights reserved.
//

import Foundation
import MovieWebService
import MovieDataBase

/// repository handler. serves as a separator of the module layers.
/// this separates the ui layer from the data layer,
/// all ui calls should have been abstracted meaning that repository
/// handles all the complex logic from retreiving data from remote api
/// and saving it into the local store
public class RepositoryHandler: Repository {
    
    private let database: Storage
    
    private let service: Service
    
    public init(database: Storage, service: Service) {
        self.database = database
        self.service = service
        self.database.loadInitConfig()
        NotificationCenter.default.addObserver(self
            , selector: #selector(appEnteredBackground)
            , name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func loadGenres(completion: @escaping ([Genre]?, Error?) -> Void) {
        
        // verifies that the app has internet conectivity
        if !service.isConnectedToInternet() {
            DispatchQueue.main.async {
                completion(nil, MoviesError(message: "app could not connect to internet"))
            }
            return
        }
        
        // loads data from the remote api tv series genres
        service.loadData(byCategory: GenreEndpoint.tvGenreList
        ,withResponseType: GenreResponse.self) { (response, error) in
            guard let responseTV = response else {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }
            // loads data from the remote api tv series genres
            self.service.loadData(byCategory: GenreEndpoint.moviesGenreList
                , withResponseType: GenreResponse.self, completion: { (response, error) in
                    guard let responseMovie = response else {
                        DispatchQueue.main.async {
                            completion(nil, error)
                        }
                        return
                    }
                    var generes = responseTV.genres
                    generes.append(contentsOf: responseMovie.genres)
                    NSLog("genre tv series items = %i", generes.count)
            })
        }
    }
    
    public func fetchMovies(pageNumber: Int = 1, completion: @escaping ([Movie]?, Error?) -> Void) {
        let parameters = ParameterBuilder().pageNumber(page: pageNumber).build()
        if service.isConnectedToInternet() {
            service.loadData(byCategory: MovieEndpoint.topRated, withResponseType: MoviesResponse.self, withParameters: parameters) { (response, error) in
                guard let results = response?.results else {
                    NSLog(error!.localizedDescription)
                    self.fetchMoviesFromDatabase(pageNumber: pageNumber, completion: completion)
                    return
                }
                for remoteMovie in results {
                    let predicate = NSPredicate(format: "id == %ld", remoteMovie.id)
                    self.database.fetch(type: Movie.self, predicate: predicate, sorted: nil, completion: { [unowned self] (movieList) in
                        if let movie = movieList?.first {
                            NSLog("title = %@ , id = %ld, pagenumber = %ld", movie.title!, movie.id, pageNumber)
                        } else {
                            self.database.createObject(type: Movie.self) { movieObj in
                                movieObj.backdropPath = remoteMovie.backdropPath
                                movieObj.posterPath = remoteMovie.posterPath
                                movieObj.title = remoteMovie.title
                                movieObj.id = Int32(remoteMovie.id)
                                movieObj.originalTitle = remoteMovie.originalTitle
                                movieObj.overview = remoteMovie.overview
                                movieObj.pageNumber = Int32(pageNumber)
                                movieObj.popularity = remoteMovie.popularity
                                movieObj.voteAverage = remoteMovie.voteAverage
                                movieObj.releaseDate = remoteMovie.releaseDate.toDate()
                            }
                        }
                    })
                }
                self.database.save() {
                    self.fetchMoviesFromDatabase(pageNumber: pageNumber, completion: completion)
                }
            }
        } else {
            self.fetchMoviesFromDatabase(pageNumber: pageNumber, completion: completion)
        }
    }
    
    private func fetchMoviesFromDatabase(pageNumber: Int, completion: @escaping ([Movie]?, Error?) -> Void) {
        let predicate = NSPredicate(format: "pageNumber == %@", String(pageNumber))
        database.fetch(type: Movie.self, predicate: predicate, sorted: Sorted(key: "creationDate", ascending: true)) { (movieList) in
            guard let movieList = movieList else {
                DispatchQueue.main.async {
                    completion(nil, MoviesError(message: "could not retrieve data from local store."))
                }
                return
            }
            DispatchQueue.main.async {
                completion(movieList, nil)
            }
        }
    }
    
    public func fetchMovieImage(movie: Movie, imageType: ImageType, completion: @escaping(Movie?, Error?) -> Void) {
        var filepath: String?
        var endpoint: Endpoint?
        switch imageType {
        case .backdropImage:
            filepath = movie.backdropPath
            endpoint = ImageEndpoint.defaultBackdropURL(filepath!)
            break
        case .posterImage:
            filepath = movie.posterPath
            endpoint = ImageEndpoint.defaultPosterURL(filepath!)
            break
        }
        
        service.donwloadData(byCategory: endpoint!) { (data, error) in
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }
            DispatchQueue.main.async {
                switch imageType {
                case .backdropImage:
                    movie.backdropImage = data
                    break
                case .posterImage:
                    movie.posterImage = data
                    break
                }
                self.database.save() {
                    completion(movie, nil)
                }
            }
        }
    }
    
    
    // todo: this responsibility should be handled on db not on repository abstraction
    @objc private func appEnteredBackground() {
        NSLog("entered appEnteredBackground")
        self.database.save()
    }
    
}
