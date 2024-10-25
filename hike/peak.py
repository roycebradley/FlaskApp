from flask import Flask, render_template, jsonify 
import logging


#logging.basicConfig(filename='flaskapp2.log', format="%(levelname)s:%(name)s:%(message)s")
logging.basicConfig(filename='/logs/flask_app.log', level=logging.INFO)

app = Flask(__name__)

@app.route('/')
def index():
    app.logger.info("Index page accessed")
    return render_template('index.html')

@app.route('/health')
def health():
    app.logger.info('Health Check')
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
