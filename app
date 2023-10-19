import datetime
import firebase_admin
import random
from firebase_admin import credentials, firestore, storage
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify


# Initializing Firebase with the service account key:
cred = credentials.Certificate("FirebaseDatabaseKey.json")
firebase_admin.initialize_app(cred, {
    'storageBucket': 'webapp-4cb99.appspot.com'
})

#Initializing Firestore and Cloud Storage:
db = firestore.client()
bucket = storage.bucket()

#Creating a Flask web application instance:
app = Flask(__name__)
app.secret_key = ''

#Defining home page route:
@app.route('/')
def index():
    #Retriving items from Firestore:
    items_ref = db.collection('items')
    items = items_ref.stream()
    #Rendering the index.html template with the retrieved items:
    return render_template('index.html', items=items)

#Function for generating a unique 7-digit item ID:
def generate_item_id():
    while True:
        item_id = str(random.randint(1000000, 9999999))
        item_ref = db.collection('items').document(item_id)
        if not item_ref.get().exists:
            return item_id

#Defining adding a new item route:
@app.route('/add', methods=['POST'])
def add_item():
    #Retrieving item information using POST request:
    name = request.form['name']
    description = request.form['description']
    category = request.form['category']
    price = request.form['price']
    image = request.files['image']

    #Generating a unique 7-digit item ID:
    itemID = generate_item_id()

    #Getting the current timestamp:
    createdAt = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    #Checking if the image file is provided and is an image:
    if image and 'image' in image.mimetype:
        image_name = f"{name}.jpg"
        blob = bucket.blob(image_name)
        blob.upload_from_file(image)
        image_url = blob.generate_signed_url(datetime.timedelta(seconds=3600), method='GET')

        #Adding item information to Firestore:
        db.collection('items').document(itemID).set({
            'name': name,
            'description': description,
            'category': category,
            'price': price,
            'image': image_url,
            'createdAt': createdAt,
            'updated_at': createdAt
        })
    else:
        flash('Only image files are allowed!', 'error')
    return redirect(url_for('index'))

#Defining editing an item route:
@app.route('/edit/<item_id>', methods=['POST'])
def edit_item(item_id):
    item_ref = db.collection('items').document(item_id)
    if request.method == 'POST':
        name = request.form['name']
        description = request.form['description']
        category = request.form['category']
        price = request.form['price']

        updatedAt = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Initializing update_data dictionary with the fields that are always updated:
        update_data = {
            'name': name,
            'description': description,
            'category': category,
            'price': price,
            'updatedAt': updatedAt
        }

        # Checking for an image in the uploaded files:
        if 'image' in request.files and request.files['image']:
            image = request.files['image']
            image_name = f"{name}.jpg"
            blob = bucket.blob(image_name)
            blob.upload_from_file(image)
            image_url = blob.generate_signed_url(datetime.timedelta(seconds=3600), method='GET')
            update_data['image'] = image_url  # Add new image URL to the update data

        # Updating the item in Firestore:
        item_ref.update(update_data)

        return jsonify({"success": True, "message": "Item updated successfully"})

    item = item_ref.get().to_dict()
    return jsonify(item)

#Defining deleting an item route:
@app.route('/delete/<item_id>')
def delete_item(item_id):
    db.collection('items').document(item_id).delete()
    return redirect(url_for('index'))

#Defining sort item route:
@app.route('/sort/<string:by>')
def sort_items(by):
    if by == 'name':
        items_ref = db.collection('items').order_by('name').stream()
    else:
        items_ref = db.collection('items').stream()
    return render_template('index.html', items=items_ref)

#Defining searching item route:
@app.route('/search', methods=['POST'])
def search_item():
    keyword = request.form['keyword']
    filter_criteria = request.form['filter_criteria']  # Added filter criteria

    items_ref = db.collection('items')
    items = items_ref.stream()

    if filter_criteria == 'name':
        filtered_items = [item for item in items if keyword.lower() in item.to_dict()['name'].lower()]
    elif filter_criteria == 'category':
        filtered_items = [item for item in items if keyword.lower() in item.to_dict()['category'].lower()]
    elif filter_criteria == 'id':
        filtered_items = [item for item in items if keyword == item.id]
    else:
        flash('Invalid filter criteria', 'error')
        return redirect(url_for('index'))

    return render_template('index.html', items=filtered_items)

#Starting the Flask Application:
if __name__ == '__main__':
    app.run(debug=True)
