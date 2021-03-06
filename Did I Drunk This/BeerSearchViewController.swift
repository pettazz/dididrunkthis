//
//  ViewController.swift
//  Did I Drunk This
//
//  Created by Nick Pettazzoni on 8/5/18.
//  Copyright © 2018 Nick Pettazzoni. All rights reserved.
//

import UIKit
import os.log

import Alamofire
import AlamofireImage
import SwiftyJSON

class BeerSearchViewController: UIViewController, UISearchResultsUpdating, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties
    @IBOutlet var tableView: UITableView!

    var foundBeers = [Beer]()
    var keepExistingSearch = false //skip the next update request

    let searchController = UISearchController(searchResultsController: nil)
    let untappdMachine = UntappdService()

    lazy var debouncedPerformSearch: (String) -> Void = debounce(delay: 1, action: self.performSearch)

    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Beer or Brewery Name"
        searchController.searchBar.searchBarStyle = .prominent
        searchController.searchBar.barStyle = .black
        tableView.tableHeaderView = searchController.searchBar

        definesPresentationContext = true

        // if this is the first time opening the app, trigger the onboard/login
        untappdMachine.ensureTokenExists(onboardingViewController: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIApplication.shared.statusBarStyle = .lightContent
        navigationController!.navigationBar.barTintColor = UIColor.darkGray
    }

    // MARK: - Private methods
    func searchContentIsEmptyOrTooSmall() -> Bool {
        return searchController.searchBar.text?.isEmpty ?? true ||
               searchController.searchBar.text?.count ?? 0 < 3
    }

    func performSearch(_ searchText: String) {
        // loading spinner
        if(searchController.isActive){
            let indicator = UIActivityIndicatorView(style: .gray)
            indicator.tag = 101
            indicator.center = self.tableView.convert(self.tableView.center, from:self.tableView.superview)

            self.tableView.addSubview(indicator)
            indicator.startAnimating()
        }

        untappdMachine.beerSearch(
            searchText: searchText,
            onSuccess: {json, rateLimitRemaining in
                var newBeerList = [Beer]()
                let responseBeers = json["response"]["beers"]["items"]

                os_log("got %u beers", type: .debug, responseBeers.count)
                for(_, subJson):(String, JSON) in responseBeers{
                    let newBeer = Beer(
                        id: subJson["beer"]["bid"].intValue,
                        name: subJson["beer"]["beer_name"].stringValue,
                        brewery: subJson["brewery"]["brewery_name"].stringValue,
                        image: UIImage(),
                        imageURL: subJson["beer"]["beer_label"].stringValue,
                        drunk: subJson["have_had"].boolValue,
                        meRating: subJson["beer"]["auth_rating"].doubleValue
                    )
                    Alamofire.request(newBeer.imageURL).responseImage { response in
                        newBeer.image = response.result.value ?? UIImage(named: "beerPlaceholder")!
                    }
                    newBeerList.append(newBeer)
                }
                self.foundBeers = newBeerList

                //TODO: bleh this is terrible
                self.tableView.viewWithTag(101)?.removeFromSuperview()

                self.tableView.reloadData()
            },
            onError: {error, rateLimitRemaining, errorTitle, errorMessage in
                //TODO: better error handling
                self.tableView.viewWithTag(101)?.removeFromSuperview()

                let alert = UIAlertController(title: errorTitle, message: errorMessage, preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .cancel))
                self.present(alert, animated: true, completion: nil)
            }
        )
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return foundBeers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "beerCell", for: indexPath) as? BeerTableViewCell else {
            fatalError("bad table cell given")
        }
        let beer: Beer

        beer = foundBeers[indexPath.row]

        cell.nameLabel!.text = beer.name
        cell.breweryLabel!.text = beer.brewery
        cell.labelImage.af_setImage(
            withURL: URL(string: beer.imageURL)!,
            placeholderImage: UIImage(named: "beerPlaceholder")!,
            completion: { response in
                beer.image = response.result.value ?? UIImage(named: "beerPlaceholder")!
        })
        cell.ratingImage.isHidden = !beer.drunk
        cell.ratingLabel.isHidden = !beer.drunk
        cell.ratingLabel.text = String(beer.meRating)

        return cell
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let selectedBeer = foundBeers[indexPath.row]
        let title = "Check In"

        let action = UIContextualAction(style: .normal,
                                        title: title,
                                        handler: { (_, _, completionHandler) in
                                            self.performSegue(withIdentifier: "checkinSegue", sender: selectedBeer)
                                            completionHandler(true)
        })
        
        //action.image = UIImage(named: "ratingBackground")
        action.backgroundColor = .blue
        let configuration = UISwipeActionsConfiguration(actions: [action])
        return configuration
    }

    // MARK: - UISearchResultsUpdating Delegate
    func updateSearchResults(for searchController: UISearchController) {
        if(self.keepExistingSearch){
            self.keepExistingSearch = false
        }else{
            if(searchContentIsEmptyOrTooSmall()){
                self.foundBeers = [Beer]()
                self.tableView.reloadData()
            }else{
                self.debouncedPerformSearch(searchController.searchBar.text!)
            }
        }
    }

    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier {
            case "detailViewSegue":
                guard let beerDetailController = segue.destination as? BeerDetailViewController else {
                    fatalError("Unexpected destination: \(segue.destination)")
                }
                
                guard let selectedBeerCell = sender as? BeerTableViewCell else {
                    fatalError("Unexpected sender: \(String(describing: sender))")
                }
                
                guard let indexPath = tableView.indexPath(for: selectedBeerCell) else {
                    fatalError("The selected cell is not being displayed by the table")
                }
                
                let selectedBeer = foundBeers[indexPath.row]
                beerDetailController.beer = selectedBeer
                beerDetailController.beerLabelImage = selectedBeer.image
                
                self.keepExistingSearch = true
            case "checkinSegue":
                guard let checkinController = segue.destination as? CheckinViewController else {
                    fatalError("Unexpected destination: \(segue.destination)")
                }
                
                guard let selectedBeer = sender as? Beer else {
                    fatalError("Unexpected sender: \(String(describing: sender))")
                }
            
                checkinController.beer = selectedBeer
            default:
                break
        }
    }
}
